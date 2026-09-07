############################################################
# Outputs
#
# Packer locates the network/SG by deterministic tag filters (Project + Purpose
# + a resource-specific Name) and the instance profile by its exact name, so it
# does NOT consume these outputs. They exist for operators, for cross-checking,
# and for the runbook.
############################################################

output "build_vpc_id" {
  description = "ID of the persistent Packer build VPC"
  value       = aws_vpc.build.id
}

output "build_subnet_id" {
  description = "ID of the single Packer build subnet"
  value       = aws_subnet.build.id
}

output "build_security_group_id" {
  description = "ID of the dedicated Packer builder security group (no ingress)"
  value       = aws_security_group.build.id
}

output "build_instance_profile_name" {
  description = "Name of the instance profile Packer attaches to the temporary builder"
  value       = aws_iam_instance_profile.build_ssm.name
}

output "build_ssm_role_arn" {
  description = "ARN of the builder IAM role — the Packer execution policy scopes iam:PassRole to exactly this ARN"
  value       = aws_iam_role.build_ssm.arn
}

output "packer_execution_role_arn" {
  description = "IAM role the operator assumes to run `packer build` — set as the Packer var packer_execution_role_arn"
  value       = aws_iam_role.packer_execution.arn
}

output "packer_selectors" {
  description = "Deterministic tag selectors Packer filters on — must match packer/wazuh-ami.pkr.hcl exactly"

  value = {
    common = {
      "tag:Project" = var.project_name
      "tag:Purpose" = local.purpose
    }
    vpc_name    = local.name_vpc
    subnet_name = local.name_subnet
    sg_name     = local.name_sg
  }
}
