#!/bin/bash

# Initial setup attempt to auth github actions to AWS resources w/o using explicit secrets
# Resources:
#   https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
#   https://aws.amazon.com/blogs/security/use-iam-roles-to-connect-github-actions-to-actions-in-aws/
# Prerequisies:
#   - aws cli installed and configured to use admin credentials

aws_account="312560106906"  # Reich Lab AWS account
hub_name="s3-testhub"  # We'll use hub name as the S3 bucket name
org_name="Infectious-Disease-Modeling-Hubs"  # the hub's GitHub org
repo_name="s3-testhub" # in case the repo name <> hub name
role_name="${hub_name}-githubaction"  # Role that will be assumed by github actions"
tags="Key=Hub,Value=${hub_name}"  # TODO: make this work with multiple tags and tagsets

# TODO:
# better error handling when a resource already exists
# could probably be clever and do some jq just with the output so we don't have to manually contruct the ARNs

# Create the OIDC provider
# The thumbprint below was retrieved via AWS console on 2024-01-30
echo "Creating an AWS OIDC provider for use with GitHub Actions..."
output=$(aws iam create-open-id-connect-provider --url "https://token.actions.githubusercontent.com" --thumbprint-list "1b511abead59c6ce207077c0bf0e0043b1382612" --client-id-list "sts.amazonaws.com" --tags ${tags})
echo -e "$output\n"

# Create s3 bucket: versioning enabled and publicly-readable
echo "Creating an S3 bucket for the hub: ${hub_name}..."
output=$(aws s3api create-bucket --bucket ${hub_name} --region us-east-1)
echo -e "$output\n"
if [ $? -ne 0 ]; then
    echo "Error creating S3 bucket"
    return 1
fi

# Tag s3 bucket
echo "Tagging S3 bucket..."
aws s3api put-bucket-tagging --bucket ${hub_name} --tagging "TagSet=[{${tags}}]"

# Enable bucket versioning
echo "Enabling bucket versioning..."
aws s3api put-bucket-versioning --bucket ${hub_name} --versioning-configuration Status=Enabled

# Make bucket publicly readable
# TODO: revisit this settings...we might need RestrictPublicBuckets to be false to make hub_connect work
echo "Making the bucket publicly readable..."
aws s3api put-public-access-block --bucket ${hub_name} --public-access-block-configuration '{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": false,
    "RestrictPublicBuckets": false
}'

aws s3api put-bucket-policy --bucket ${hub_name} --policy '{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::'${hub_name}'/*"
            ]
        },
        {
            "Sid": "PublicListBucket",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::'${hub_name}'"
            ]
        }
    ]
}'

if [ $? -ne 0 ]; then
    echo "Error enablinb public access to S3 bucket"
    return 1
fi

# Create a policy that allows writing to the hub's S3 bucket
echo "Creating an IAM policy that provides write access to the hub's S3 bucket: ${role_name}-policy..."
s3_policy_document=$(
cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket",
                "s3:PutObject",
                "s3:PutObjectAcl"
             ],
             "Resource": [
                "arn:aws:s3:::${hub_name}",
                "arn:aws:s3:::${hub_name}/*"
            ]
        }
    ]
}
EOF
)
output=$(aws iam create-policy --policy-name ${role_name}-policy --tags ${tags} --policy-document ${s3_policy_document})
if [ $? -ne 0 ]; then
    echo "Error creating IAM policy"
    return 1
fi
echo -e "$output\n"

# create a role that will be used in conjunction with the above policy to permit write operations to the bucket
echo "Creating the IAM role that will be assumed by GitHub Actions: ${role_name}..."
policy_document=$(
cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${aws_account}:oidc-provider/token.actions.githubusercontent.com"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "token.actions.githubusercontent.com:sub": "repo:${org_name}/${hub_name}:ref:refs/heads/main",
                    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
EOF
)
# output=$(aws iam create-role --role-name ${role_name} --tags ${tags} --assume-role-policy-document '{
output=$(aws iam create-role --role-name ${role_name} --tags ${tags} --assume-role-policy-document ${policy_document})
if [ $? -ne 0 ]; then
    echo "Error creating IAM role"
    return 1
fi
echo -e "$output\n"

# Attach the policy to the role
echo "Attaching the S3 write policy to the GitHub actions role..."
aws iam attach-role-policy --role-name ${role_name} --policy-arn arn:aws:iam::${aws_account}:policy/${role_name}-policy

