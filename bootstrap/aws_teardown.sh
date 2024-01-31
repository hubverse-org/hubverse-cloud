#!/bin/bash

# Teardown the AWS resources created for this test repo
# Prerequisies:
#   - aws cli installed and configured to use admin credentials

aws_account="312560106906"  # Reich Lab AWS account
hub_name="s3-testhub"  # We'll use hub name as the S3 bucket name
org_name="Infectious-Disease-Modeling-Hubs"  # the hub's GitHub org
repo_name="s3-testhub" # in case the repo name <> hub name
role_name="${hub_name}-githubaction"  # Role that will be assumed by github actions"


aws s3 rm s3://${hub_name}
aws iam detach-role-policy --role-name ${role_name} --policy-arn arn:aws:iam::${aws_account}:policy/${role_name}-policy
aws iam delete-policy --policy-arn arn:aws:iam::${aws_account}:policy/${role_name}-policy
aws iam delete-role --role-name ${role_name}
aws iam delete-open-id-connect-provider --open-id-connect-provider-arn arn:aws:iam::${aws_account}:oidc-provider/token.actions.githubusercontent.com