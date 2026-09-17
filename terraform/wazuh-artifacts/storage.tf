############################################################
# Persistent S3 bucket for the Wazuh Compose file and configuration
#
# Security-account-owned (D-014). The Wazuh runtime in the Lab account reads the
# stack definition from s3://<bucket>/wazuh/ at first boot. Cross-account read
# permission is granted unconditionally below to var.lab_runtime_role_arn
# (required — D-018; that role is created by the persistent
# terraform/wazuh-runtime-identity/ root, applied before this one).
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
# Bucket policy: TLS enforcement + Lab-account read, both unconditional
#
# TLS-deny is a Deny statement, not a public-access grant, so it coexists with
# block_public_policy = true.
#
# The Lab-read statements are a resource-based grant, required IN ADDITION to
# the Lab runtime's own identity-based policy
# (terraform/wazuh-runtime-identity/iam.tf) — S3 needs both sides to agree for
# cross-account access. Unconditional (D-018): var.lab_runtime_role_arn is
# required, and the role it names already exists (created by the persistent
# terraform/wazuh-runtime-identity/ root, applied before this one). Scoped to
# the `wazuh/*` prefix only — never the whole bucket.
############################################################

locals {
  s3_policy_statements = [
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
    },
    {
      Sid    = "AllowLabRuntimeReadWazuhPrefix"
      Effect = "Allow"

      Principal = {
        AWS = var.lab_runtime_role_arn
      }

      Action   = "s3:GetObject"
      Resource = "${aws_s3_bucket.wazuh_artifacts.arn}/wazuh/*"
    },
    {
      Sid    = "AllowLabRuntimeListWazuhPrefix"
      Effect = "Allow"

      Principal = {
        AWS = var.lab_runtime_role_arn
      }

      Action   = "s3:ListBucket"
      Resource = aws_s3_bucket.wazuh_artifacts.arn

      Condition = {
        StringLike = {
          "s3:prefix" = ["wazuh/*"]
        }
      }
    }
  ]
}

resource "aws_s3_bucket_policy" "wazuh_artifacts" {
  bucket = aws_s3_bucket.wazuh_artifacts.id

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = local.s3_policy_statements
  })

  depends_on = [aws_s3_bucket_public_access_block.wazuh_artifacts]
}
