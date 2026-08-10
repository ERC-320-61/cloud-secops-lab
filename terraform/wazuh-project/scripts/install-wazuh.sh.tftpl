#!/bin/bash
set -euxo pipefail

############################################################
# Configure user-data logging for troubleshooting
############################################################

exec > >(tee /var/log/wazuh-user-data.log \
  | logger -t user-data -s 2>/dev/console) 2>&1


############################################################
# Define deployment variables
############################################################

AWS_REGION="${aws_region}"
WAZUH_DIR="/opt/wazuh-docker"
ARTIFACT_BUCKET="${artifact_bucket}"


############################################################
# Get AWS account ID and build the private ECR registry address
############################################################

ACCOUNT_ID=$(aws sts get-caller-identity \
    --query Account \
    --output text)

ECR_REGISTRY="$${ACCOUNT_ID}.dkr.ecr.$${AWS_REGION}.amazonaws.com"


############################################################
# Download Wazuh configuration from the private S3 bucket
############################################################

aws s3 sync \
    "s3://$${ARTIFACT_BUCKET}/wazuh/" \
    "$${WAZUH_DIR}/single-node/"


############################################################
# Authenticate Docker to the private Amazon ECR registry
############################################################

aws ecr get-login-password \
    --region "$${AWS_REGION}" \
| docker login \
    --username AWS \
    --password-stdin \
    "$${ECR_REGISTRY}"


############################################################
# Change to the Wazuh single-node deployment directory
############################################################

cd "$${WAZUH_DIR}/single-node"


############################################################
# Pull the Wazuh container images from Amazon ECR
############################################################

docker compose pull


############################################################
# Generate certificates for the Wazuh deployment
############################################################

docker compose \
    -f generate-indexer-certs.yml \
    run --rm generator


############################################################
# Start the Wazuh single-node Docker stack
############################################################

docker compose up -d