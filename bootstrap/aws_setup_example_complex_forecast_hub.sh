#!/bin/bash

# Building on the intiial setup, add a bucket and policy for storing data in example-complex-forecast-hub
# TODO: if this is the pattern we adopt for S3, this stuff should be handled via Terraform repo
# Prerequisies:
#   - aws cli installed and configured to use admin credentials

aws_account="312560106906"  # Reich Lab AWS account

# names for the bucket and role for use with GitHub Actions
hub_name="example-complex-forecast-hub" 
bucket_name="hubverse-${hub_name}"  # use hub name as the S3 bucket name, but prefix to avoid S3 name conflicts
role_name="hubverse-${hub_name}-githubaction"  # Role that will be assumed by github actions"

# names for GitHub org and repo: used to define specific GitHub entites that are allowed to assume the role
org_name="Infectious-Disease-Modeling-Hubs"  # the hub's GitHub org
repo_name="example-complex-forecast-hub" # in case the repo name <> hub name

# used to add a "hubverse" tag to the S3 resources we're creating here
tags="Key=hubverse,Value=true"  # TODO: make this work with multiple tags and tagsets

# Create s3 bucket: versioning enabled and publicly-readable
echo "Creating an S3 bucket for the hub: ${bucket_name}..."
output=$(aws s3api create-bucket --bucket ${bucket_name} --region us-east-1)
echo -e "$output\n"
if [ $? -ne 0 ]; then
    echo "Error creating S3 bucket"
    return 1
fi

# Tag s3 bucket
echo "Tagging S3 bucket..."
aws s3api put-bucket-tagging --bucket ${bucket_name} --tagging "TagSet=[{${tags}}]"

# Enable bucket versioning
echo "Enabling bucket versioning..."
aws s3api put-bucket-versioning --bucket ${bucket_name} --versioning-configuration Status=Enabled

# Make bucket publicly readable
echo "Making the bucket publicly readable..."
aws s3api put-public-access-block --bucket ${bucket_name} --public-access-block-configuration '{
    "BlockPublicAcls": true,
    "IgnorePublicAcls": true,
    "BlockPublicPolicy": false,
    "RestrictPublicBuckets": false
}'

aws s3api put-bucket-policy --bucket ${bucket_name} --policy '{
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
                "arn:aws:s3:::'${bucket_name}'/*"
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
                "arn:aws:s3:::'${bucket_name}'"
            ]
        }
    ]
}'

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
                "arn:aws:s3:::${bucket_name}",
                "arn:aws:s3:::${bucket_name}/*"
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
# (github actions OIDC provider already exists in the Reich Lab AWS account)
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
                    "token.actions.githubusercontent.com:sub": "repo:${org_name}/${repo_name}:ref:refs/heads/main",
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
echo -e "$output\n"

# Attach the policy to the role
echo "Attaching the S3 write policy to the GitHub actions role..."
aws iam attach-role-policy --role-name ${role_name} --policy-arn arn:aws:iam::${aws_account}:policy/${role_name}-policy

