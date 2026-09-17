############################################################
# Provider requirements for the persistent Wazuh artifact layer
#
# One of four Terraform roots (docs/DECISIONS.md D-016 / D-018), separate from:
#   - terraform/wazuh-runtime-identity/ — persistent Lab runtime IAM identity (Lab account)
#   - terraform/wazuh-project/          — disposable Wazuh runtime (Lab account)
#   - terraform/packer-build/           — persistent Packer build network (Security account)
#
# Lifecycle: PERSISTENT. This root owns the private container registry and the
# artifact/config bucket that survive between Wazuh runtime deploy -> test ->
# validate -> destroy cycles. It is NOT destroyed as part of that cycle.
#
# Account placement (D-014): applied in the SECURITY account with the
# `security-admin` permission set. The account ID is discovered at apply time
# (data.aws_caller_identity) — nothing here hard-codes an account.
#
# Dependency order (D-018 — one-directional, no circular apply): this root is
# applied AFTER terraform/wazuh-runtime-identity/ (which must already have
# created the Lab role this root grants access to) and BEFORE
# terraform/wazuh-project/ (which consumes this root's outputs). This root has
# no Terraform dependency on terraform/wazuh-project/ at all.
#
# Scope of THIS root: the persistent ECR repositories, the S3 bucket, and the
# narrow cross-account resource policies (aws_ecr_repository_policy,
# aws_s3_bucket_policy) that let the named Lab runtime role
# (var.lab_runtime_role_arn, required) pull/read them — granted unconditionally
# in a single apply. It deliberately does NOT contain the image-mirror
# workflow, the Wazuh Compose/config artifact set, certificates, runtime
# bootstrap, runtime EC2, or any Security Hub / EventBridge integration
# (B2/B3 and later phases).
############################################################

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.57.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
