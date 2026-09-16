############################################################
# Persistent S3 bucket for the Wazuh Compose file and configuration
#
# Security-account-owned (D-014). The Wazuh runtime in the Lab account reads the
# stack definition from s3://<bucket>/wazuh/ at first boot. Cross-account read
# permission (a bucket policy for the runtime instance role) is NOT added here
# yet — see docs/CURRENT_STATE.md "next work".
#
# Encryption decision (D-016, folds in D-010): SSE-S3 (AES256) at rest and TLS
# enforced in transit for Phase 1. A customer-managed KMS key (SSE-KMS) is
# deferred as a later hardening exercise.
############################################################

data "aws_caller_identity" "current" {}


############################################################
# Bucket (globally unique name via the account ID)
############################################################

resource "aws_s3_bucket" "wazuh_artifacts" {
  bucket = "${var.project_name}-artifacts-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-wazuh-artifacts"
  })
}


############################################################
# Block all forms of public access
############################################################

resource "aws_s3_bucket_public_access_block" "wazuh_artifacts" {
  bucket = aws_s3_bucket.wazuh_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}


############################################################
# SSE-S3 (AES256) server-side encryption at rest
############################################################

resource "aws_s3_bucket_server_side_encryption_configuration" "wazuh_artifacts" {
  bucket = aws_s3_bucket.wazuh_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


############################################################
# Enforce TLS in transit: deny any request made over plain HTTP
#
# This is a Deny statement, not a public-access grant, so it coexists with
# block_public_policy = true.
############################################################

resource "aws_s3_bucket_policy" "wazuh_artifacts" {
  bucket = aws_s3_bucket.wazuh_artifacts.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid       = "DenyNonTLSRequests"
        Effect    = "Deny"
        Principal = "*"

        Action = "s3:*"

        Resource = [
          aws_s3_bucket.wazuh_artifacts.arn,
          "${aws_s3_bucket.wazuh_artifacts.arn}/*",
        ]

        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.wazuh_artifacts]
}
