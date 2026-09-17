############################################################
# Project name used for AWS resource names and tags
#
# Must match terraform/wazuh-project/ and terraform/wazuh-artifacts/ (default
# "cloud-secops-lab" everywhere) — it feeds into the deterministic ECR/S3 ARNs
# below and must resolve to the same names those roots use.
############################################################

variable "project_name" {
  description = "Name used for AWS resource names and tags"
  type        = string
  default     = "cloud-secops-lab"
}


############################################################
# AWS Region — must match terraform/wazuh-artifacts/ (default us-east-2)
############################################################

variable "aws_region" {
  description = "AWS Region for the Lab runtime identity (must match where terraform/wazuh-artifacts/ is applied)"
  type        = string
  default     = "us-east-2"
}


############################################################
# Security account ID (cross-account, deterministic-ARN construction — D-018)
#
# This root is applied BEFORE terraform/wazuh-artifacts/ in the dependency
# order (D-018), so it cannot read that root's live outputs for its own
# least-privilege IAM policy. Instead, the ECR repository ARNs and the S3
# bucket ARN are constructed deterministically from this account ID plus the
# naming convention terraform/wazuh-artifacts/ uses
# (`${project_name}/<repo>` for ECR, `${project_name}-artifacts-${account_id}`
# for S3 — see iam.tf). If that naming convention ever changes, update it
# here too; the two roots are coupled by convention, not by Terraform state.
#
# Required — no default. Non-secret account metadata (the same kind of value
# already used as `lab_account_id` for the Packer AMI share, D-015) — never
# invented; supply the real Security account ID.
############################################################

variable "security_account_id" {
  description = "AWS account ID of the Security account that owns the Wazuh ECR repositories and S3 artifact bucket (terraform/wazuh-artifacts/). Required — no default. Non-secret account metadata, used only to construct this role's least-privilege resource ARNs."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.security_account_id))
    error_message = "security_account_id must be a 12-digit AWS account ID."
  }
}
