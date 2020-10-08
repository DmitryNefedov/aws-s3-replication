#!/usr/bin/env bash

# based on
# https://docs.aws.amazon.com/AmazonS3/latest/dev/replication-walkthrough1.html
# https://docs.aws.amazon.com/AmazonS3/latest/dev/replication-walkthrough-2.html
# https://docs.aws.amazon.com/AmazonS3/latest/dev/replication-change-owner.html

set -eux

SOURCE_AWS_PROFILE=${1}
DESTINATION_AWS_PROFILE=${2}
ENV=${3}

SOURCE_BUCKET=${4}
DESTINATION_BUCKET=${5}

SOURCE_REPL_ROLE_NAME=crossAccountReplicationRole-${ENV}

mkdir -p ${ENV}
cp templates/*.json ${ENV}

# Create IAM role in source account
aws iam create-role \
  --role-name ${SOURCE_REPL_ROLE_NAME} \
  --assume-role-policy-document file://${ENV}/s3-role-trust-policy.json  \
  --profile ${SOURCE_AWS_PROFILE}

# Add necessary policies to IAM role in source account
sed -i "s+__SOURCE_BUCKET__+${SOURCE_BUCKET}+g" ${ENV}/s3-role-permissions-policy.json
sed -i "s+__DESTINATION_BUCKET__+${DESTINATION_BUCKET}+g" ${ENV}/s3-role-permissions-policy.json
aws iam put-role-policy \
  --role-name ${SOURCE_REPL_ROLE_NAME} \
  --policy-document file://${ENV}/s3-role-permissions-policy.json \
  --policy-name replicationRolePolicy \
  --profile ${SOURCE_AWS_PROFILE}

# 'put-bucket-policy' fails with 'Invalid principal in policy' if run straight after a new role gets created or updated
sleep 5

# Set bucket-policy in destination account bucket allowing cross-account replication
SOURCE_ACCOUNT=$(aws sts get-caller-identity --profile ${SOURCE_AWS_PROFILE} | grep "Account" | awk  '{print $2}' | sed 's/"//g; s/,//g')
sed -i "s+__SOURCE_ACC_ID__+${SOURCE_ACCOUNT}+g" ${ENV}/S3-destination-bucket-policy.json
sed -i "s+__SOURCE_ROLE_NAME__+${SOURCE_REPL_ROLE_NAME}+g" ${ENV}/S3-destination-bucket-policy.json
sed -i "s+__DESTINATION_BUCKET__+${DESTINATION_BUCKET}+g" ${ENV}/S3-destination-bucket-policy.json
aws s3api put-bucket-policy \
  --bucket ${DESTINATION_BUCKET} \
  --policy file://${ENV}/S3-destination-bucket-policy.json \
  --profile ${DESTINATION_AWS_PROFILE}


# Enable replication
DESTINATION_ACCOUNT=$(aws sts get-caller-identity --profile ${DESTINATION_AWS_PROFILE} | grep "Account" | awk  '{print $2}' | sed 's/"//g; s/,//g')
sed -i "s+__DESTINATION_BUCKET__+${DESTINATION_BUCKET}+g" ${ENV}/replication.json
sed -i "s+__SOURCE_ACC_ID__+${SOURCE_ACCOUNT}+g" ${ENV}/replication.json
sed -i "s+__SOURCE_ROLE_NAME__+${SOURCE_REPL_ROLE_NAME}+g" ${ENV}/replication.json
sed -i "s+__DESTINATION_ACC_ID__+${DESTINATION_ACCOUNT}+g" ${ENV}/replication.json
aws s3api put-bucket-replication \
  --replication-configuration file://${ENV}/replication.json \
  --bucket ${SOURCE_BUCKET} \
  --profile ${SOURCE_AWS_PROFILE}


aws s3api get-bucket-replication \
  --bucket ${SOURCE_BUCKET} \
  --profile ${SOURCE_AWS_PROFILE}

rm -rf ${ENV}

echo "Replication is set between [${SOURCE_BUCKET}] and [${DESTINATION_BUCKET}]"