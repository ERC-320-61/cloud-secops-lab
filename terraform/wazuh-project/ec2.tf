############################################################
# 1. Create the Wazuh EC2 instance from the Packer-built AMI.
############################################################
resource "aws_instance" "wazuh" {
  ami           = var.wazuh_ami_id
  instance_type = var.wazuh_instance_type

  subnet_id = aws_subnet.private_1.id

  iam_instance_profile = aws_iam_instance_profile.wazuh_ec2.name

  user_data = templatefile(
    "${path.module}/scripts/install-wazuh.sh.tftpl",
    {
      aws_region      = var.aws_region
      artifact_bucket = aws_s3_bucket.wazuh_artifacts.bucket
    }
  )

  tags = {
    Name    = "${var.project_name}-wazuh"
    Project = var.project_name
  }
}