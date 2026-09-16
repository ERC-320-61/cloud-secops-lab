############################################################
# Project name used for AWS resource names and tags
############################################################

variable "project_name" {
  description = "Name used for AWS resource names and tags"
  type        = string
  default     = "cloud-secops-lab"
}


############################################################
# AWS Region for the Packer build network
############################################################

variable "aws_region" {
  description = "AWS Region for the Packer build network (must match the Packer build region)"
  type        = string
  default     = "us-east-2"
}


############################################################
# Availability Zone for the single build subnet
############################################################

variable "availability_zone" {
  description = "Availability Zone for the build subnet"
  type        = string
  default     = "us-east-2a"
}


############################################################
# CIDR ranges for the build network
#
# Kept deliberately small and clearly non-overlapping with the Wazuh runtime
# VPC (10.0.0.0/16). A /24 VPC with a single /24 subnet is all a lone
# ephemeral Packer builder needs.
############################################################

variable "build_vpc_cidr" {
  description = "CIDR range for the Packer build VPC (must not overlap the Wazuh runtime 10.0.0.0/16)"
  type        = string
  default     = "10.10.0.0/24"
}

variable "build_subnet_cidr" {
  description = "CIDR range for the single Packer build subnet"
  type        = string
  default     = "10.10.0.0/24"
}


############################################################
# Operator identity (IAM Identity Center) for the Packer execution role (PB-4)
#
# Human access is via IAM Identity Center (the instance lives in the Management
# account; Identity Center provisions AWSReservedSSO_* roles into each member
# account). This root is applied in the SECURITY account (docs/DECISIONS.md
# D-014); the trust policy therefore resolves to
#   arn:aws:iam::<security-account>:role/aws-reserved/sso.amazonaws.com/<region>/AWSReservedSSO_CloudGuardOperator_*
# where <security-account> comes from data.aws_caller_identity at apply time, so
# no account ID is committed to source. The generated AWSReservedSSO role suffix
# is matched with a wildcard and is never set here.
#
# operator_permission_set_name = "CloudGuardOperator" is the permission set the
# `security` profile assumes in the Security account for routine Packer runs.
############################################################

variable "identity_center_region" {
  description = "Region of the IAM Identity Center instance — used only to build the AWSReservedSSO role path in the execution-role trust policy"
  type        = string
  default     = "us-east-2"
}

variable "operator_permission_set_name" {
  description = "IAM Identity Center permission-set name for the normal CloudGuard operator identity (CloudGuardOperator, assumed via the `security` profile in the Security account)"
  type        = string
  default     = "CloudGuardOperator"
}
