############################################################
# Outputs
#
# This root no longer creates the Wazuh EC2 IAM role (D-018 — see
# terraform/wazuh-runtime-identity/), so there is no role ARN to output here
# any more. These outputs are the runtime completion gap (instance id / SSM
# command) closed as part of the D-019 hardening pass.
############################################################

output "instance_id" {
  description = "Instance ID of the Wazuh EC2 host"
  value       = aws_instance.wazuh.id
}

output "ssm_start_session_command" {
  description = "Ready-to-paste AWS CLI command to open an SSM shell on the Wazuh instance"
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.wazuh.id}"
}

output "security_group_id" {
  description = "ID of the dedicated Wazuh EC2 security group"
  value       = aws_security_group.wazuh_ec2.id
}
