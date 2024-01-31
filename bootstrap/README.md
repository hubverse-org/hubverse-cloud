# AWS Setup

The bash scripts in this folder were used to setup the AWS resources neeed for the S3-testhub.

They're pretty unfinished and meant to serve as a reference, not as something we'd want to run reguarly or ship to users.


## Scripts


### aws_setup.sh

This script creates the AWS resources needed to access AWS resources from GitHub Actions using an OpenID Connect (OIDC) identity provider.

Using the OIDC provider (as opposed to storing AWS access keys as repo secrets) requires more initial setup but has these advantages:

- Is the approach recommended by both GitHub and AWS
- Generates temporary AWS creds for use during a GitHub action (no need to store and rotate long-term creds)
- Once setup, works very smoothly with [AWS's supported GitHub actions](https://github.com/aws-actions)

`aws_setup.sh` creates the following AWS resources:

1. An OIDC identity provider for GitHub actions (once created, this is available across the AWS account)
2. An IAM role that can be assumed by GitHub actions*
3. An S3 bucket to store hub data
4. An IAM policy that allows write access to the bucket (and is then attached to the role created in step 2)

* In this example, the IAM role for use with GitHub actions is fairly strict, as the `Condition` states that an action must be associated with this repo's main branch to assume it.

```
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
```

### aws_teardown.sh

This script deletes the AWS resources created by `aws_setup.sh`. It's very destructive and only included here for testing.
