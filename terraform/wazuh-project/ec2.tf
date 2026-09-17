############################################################
# 1. Create the Wazuh EC2 instance from the Packer-built AMI.
#
# ami                  = var.wazuh_ami_id — the golden AMI built and owned by
#   the Security account, shared to Lab by launch permission (D-014 / D-015).
# artifact_bucket / ecr_registry — the Security-account, persistent artifact
#   resources (terraform/wazuh-artifacts/, D-016). This root does not create
#   or own them; both are explicit inputs, never discovered at apply time.
# iam_instance_profile = var.wazuh_runtime_instance_profile_name — the
#   already-existing profile from terraform/wazuh-runtime-identity/ (D-018).
#   This root does not create its own IAM role/profile.
#
# Hardening (D-019): dedicated SG (security.tf), no public IP, IMDSv2
# required, encrypted gp3 root volume.
############################################################
resource "aws_instance" "wazuh" {
  ami           = var.wazuh_ami_id
  instance_type = var.wazuh_instance_type

  subnet_id                   = aws_subnet.private_1.id
  vpc_security_group_ids      = [aws_security_group.wazuh_ec2.id]
  associate_public_ip_address = false

  iam_instance_profile = var.wazuh_runtime_instance_profile_name

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 50 # reference size for manager + indexer; revisit under real load
    encrypted             = true
    delete_on_termination = true
  }

  user_data = templatefile(
    "${path.module}/scripts/install-wazuh.sh.tftpl",
    {
      aws_region      = var.aws_region
      artifact_bucket = var.wazuh_artifact_bucket_name
      ecr_registry    = var.wazuh_ecr_registry
    }
  )

  tags = {
    Name    = "${var.project_name}-wazuh"
    Project = var.project_name
  }
}