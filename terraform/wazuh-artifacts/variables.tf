############################################################
# Project name used for AWS resource names and tags
############################################################

variable "project_name" {
  description = "Name used for AWS resource names and tags"
  type        = string
  default     = "cloud-secops-lab"
}


############################################################
# AWS Region for the persistent Wazuh artifact layer
#
# Must match the region the Wazuh runtime and the Packer build use (us-east-2)
# so the runtime can pull images / config over regional endpoints.
############################################################

variable "aws_region" {
  description = "AWS Region for the persistent Wazuh artifact layer (ECR + artifact bucket)"
  type        = string
  default     = "us-east-2"
}


############################################################
# Lab-account Wazuh runtime role (cross-account access target)
#
# Grants narrow, prefix-scoped pull/read access on the ECR repos (ecr.tf) and
# the S3 bucket (storage.tf) in this root to exactly this one role — nothing
# else.
#
# Required — no default (D-018). This is safe to require, unlike in the
# earlier design: terraform/wazuh-runtime-identity/ is a persistent root that
# creates this role and is applied BEFORE this one in the accepted dependency
# order (identity root -> wazuh-artifacts -> wazuh-project), so the role
# already exists by the time this root is applied. That makes this a single,
# one-directional apply — no conditional grant, no re-apply.
#
# Never invented here. Supply the real ARN from that root's output:
#
#   terraform -chdir=terraform/wazuh-artifacts apply \
#     -var "lab_runtime_role_arn=$(terraform -chdir=terraform/wazuh-runtime-identity output -raw wazuh_runtime_role_arn)"
############################################################

variable "lab_runtime_role_arn" {
  description = "IAM role ARN of the Lab-account Wazuh runtime EC2 instance role, from terraform/wazuh-runtime-identity output `wazuh_runtime_role_arn`. Required — no default; that root is applied first (D-018), so the role always exists by the time this one is applied. Non-secret; never invented."
  type        = string

  validation {
    condition     = can(regex("^arn:aws:iam::[0-9]{12}:role/.+$", var.lab_runtime_role_arn))
    error_message = "lab_runtime_role_arn must be a valid IAM role ARN of the form arn:aws:iam::<12-digit-account-id>:role/<role-name>."
  }
}
