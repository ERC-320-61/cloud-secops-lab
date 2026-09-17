############################################################
# Outputs
#
# Consumed by:
#   - terraform/wazuh-artifacts/ (as var.lab_runtime_role_arn, required,
#     applied AFTER this root — D-018) via `wazuh_runtime_role_arn`.
#   - terraform/wazuh-project/ (as var.wazuh_runtime_instance_profile_name)
#     via `wazuh_runtime_instance_profile_name`.
############################################################

output "wazuh_runtime_role_arn" {
  description = "ARN of the Lab-account Wazuh runtime EC2 role — supply to terraform/wazuh-artifacts/ as var.lab_runtime_role_arn"
  value       = aws_iam_role.wazuh_ec2.arn
}

output "wazuh_runtime_role_name" {
  description = "Name of the Lab-account Wazuh runtime EC2 role"
  value       = aws_iam_role.wazuh_ec2.name
}

output "wazuh_runtime_instance_profile_name" {
  description = "Name of the instance profile — supply to terraform/wazuh-project/ as var.wazuh_runtime_instance_profile_name"
  value       = aws_iam_instance_profile.wazuh_ec2.name
}
