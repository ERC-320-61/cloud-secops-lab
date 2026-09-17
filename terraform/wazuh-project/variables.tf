############################################################
# Define the project name used for AWS resource names and tags
############################################################

variable "project_name" {
  description = "Name used for AWS resource names and tags"
  type        = string
  default     = "cloud-secops-lab"
}


############################################################
# Define the AWS Region where the Wazuh lab will be deployed
############################################################

variable "aws_region" {
  description = "AWS Region for the Wazuh lab"
  type        = string
  default     = "us-east-2"
}


############################################################
# Define the Availability Zone used by the private Wazuh subnet
############################################################

variable "availability_zone" {
  description = "Availability Zone for Wazuh resources"
  type        = string
  default     = "us-east-2a"
}


############################################################
# Define the CIDR range used by the Wazuh VPC
############################################################

variable "vpc_cidr" {
  description = "CIDR range for the Wazuh VPC"
  type        = string
  default     = "10.0.0.0/16"
}


############################################################
# Define the CIDR range used by the private Wazuh subnet
############################################################

variable "subnet_cidr" {
  description = "CIDR range for the private Wazuh subnet"
  type        = string
  default     = "10.0.1.0/24"
}


############################################################
# Define the Packer-built AMI used to launch the Wazuh EC2 instance
############################################################

variable "wazuh_ami_id" {
  description = "AMI built by Packer for the Wazuh EC2 instance"
  type        = string
}


############################################################
# Define the EC2 instance size used to run the Wazuh single-node stack
############################################################

variable "wazuh_instance_type" {
  description = "EC2 instance type for the Wazuh server"
  type        = string
  default     = "c5a.xlarge"
}


############################################################
# Security-owned Wazuh artifact inputs (D-014 / D-016)
#
# This root (Lab account) does NOT own or create the Wazuh ECR repositories or
# the S3 artifact/config bucket — those are persistent, Security-account
# resources defined in terraform/wazuh-artifacts/. This root only CONSUMES the
# two pieces its EC2 user-data needs at runtime (docker login target, S3 sync
# bucket), via explicit inputs sourced from that root's outputs — never via
# data.aws_caller_identity (which would resolve to THIS account, Lab, not
# Security) and never hard-coded or guessed. (It does NOT need
# `ecr_repository_arns` — the runtime's ECR-pull IAM policy now lives in
# terraform/wazuh-runtime-identity/, not here — D-018.)
#
# Supply both from the Security apply (commands run from the repo root), e.g.:
#   export TF_VAR_wazuh_ecr_registry="$(terraform -chdir=terraform/wazuh-artifacts output -raw ecr_registry)"
#   export TF_VAR_wazuh_artifact_bucket_name="$(terraform -chdir=terraform/wazuh-artifacts output -raw artifact_bucket_name)"
############################################################

variable "wazuh_ecr_registry" {
  description = "Security-account ECR registry hostname (<account>.dkr.ecr.<region>.amazonaws.com), from terraform/wazuh-artifacts output `ecr_registry`. Required — no default; deliberately not discovered at apply time, since this root's own account (Lab) does not own the registry."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}\\.dkr\\.ecr\\.[a-z0-9-]+\\.amazonaws\\.com$", var.wazuh_ecr_registry))
    error_message = "wazuh_ecr_registry must look like <12-digit-account-id>.dkr.ecr.<region>.amazonaws.com."
  }
}

variable "wazuh_artifact_bucket_name" {
  description = "Name of the Security-account S3 bucket holding the Wazuh Compose/config artifacts, from terraform/wazuh-artifacts output `artifact_bucket_name`. Required — no default."
  type        = string
}


############################################################
# Lab runtime identity inputs (D-018)
#
# This root does NOT create the Wazuh EC2's IAM role or instance profile —
# terraform/wazuh-runtime-identity/ (persistent, applied first) does, so that
# terraform/wazuh-artifacts/ can grant it cross-account access in a single,
# one-directional apply before this root ever runs. This root only attaches
# the already-existing instance profile by name.
#
# Supply from:
#   export TF_VAR_wazuh_runtime_instance_profile_name="$(terraform -chdir=terraform/wazuh-runtime-identity output -raw wazuh_runtime_instance_profile_name)"
############################################################

variable "wazuh_runtime_instance_profile_name" {
  description = "Name of the Wazuh EC2 instance profile, from terraform/wazuh-runtime-identity output `wazuh_runtime_instance_profile_name`. Required — no default. This root does not create its own IAM role (D-018)."
  type        = string
}