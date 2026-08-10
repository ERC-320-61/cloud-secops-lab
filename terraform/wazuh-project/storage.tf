############################################################
# Get the current AWS account ID for a globally unique S3 bucket name
############################################################

data "aws_caller_identity" "current" {}


############################################################
# Create the private S3 bucket for Wazuh Compose and configuration files
############################################################

resource "aws_s3_bucket" "wazuh_artifacts" {
  bucket = "${var.project_name}-artifacts-${data.aws_caller_identity.current.account_id}"

  tags = {
    Name    = "${var.project_name}-wazuh-artifacts"
    Project = var.project_name
  }
}


############################################################
# Block all public access to the Wazuh artifact bucket
############################################################

resource "aws_s3_bucket_public_access_block" "wazuh_artifacts" {
  bucket = aws_s3_bucket.wazuh_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


############################################################
# Enable AES-256 server-side encryption for Wazuh artifact objects
############################################################

resource "aws_s3_bucket_server_side_encryption_configuration" "wazuh_artifacts" {
  bucket = aws_s3_bucket.wazuh_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}