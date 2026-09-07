############################################################
# Packer execution identity (PB-4)
#
# `packer build` starts from the operator's normal AWS credentials — an active
# IAM Identity Center session for CloudGuardOperator, e.g.
#
#     AWS_PROFILE=cloudguard packer build .
#
# — and then assumes the dedicated least-privilege execution role created by
# terraform/packer-build/ for all AWS work. No access keys, secrets, human
# usernames, or AWS account IDs are embedded here.
#
# packer_execution_role_arn is REQUIRED and has no default. Supply it from the
# Terraform output, e.g.:
#
#     export PKR_VAR_packer_execution_role_arn="$(
#       terraform -chdir=terraform/packer-build output -raw packer_execution_role_arn
#     )"
############################################################

variable "packer_execution_role_arn" {
  type        = string
  description = "ARN of cloud-secops-lab-packer-execution-role, from terraform/packer-build/ output packer_execution_role_arn. Required — no default."
}
