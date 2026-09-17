############################################################
# Provider requirements for the disposable Wazuh runtime
#
# Account placement (docs/DECISIONS.md D-014): this root is applied in the LAB
# account, with the `lab-admin` permission set (AdministratorAccess in Lab) for
# now, or a dedicated runtime execution role later. It stays on the
# deploy -> test -> validate -> destroy cycle (D-006) — unlike the two
# persistent roots it depends on.
#
# This root does NOT call data.aws_caller_identity and owns NEITHER the Wazuh
# ECR repositories / S3 artifact bucket (persistent, Security account —
# terraform/wazuh-artifacts/, D-016) NOR the EC2 IAM role / instance profile
# (persistent, Lab account — terraform/wazuh-runtime-identity/, D-018). It
# only CONSUMES both, via explicit variables sourced from their outputs —
# never discovered at apply time, never duplicated here.
#
# Dependency order (D-018 — one-directional, no circular apply):
#   1. terraform/wazuh-runtime-identity/  (Lab, persistent)
#   2. terraform/wazuh-artifacts/         (Security, persistent) — grants
#      cross-account access to step 1's role in a single apply
#   3. terraform/wazuh-project/           (this root, Lab, disposable)
#
# Migration note: this root used to also create the ECR repositories, the S3
# artifact bucket (removed, D-017), and its own copy of the EC2 IAM role
# (removed, D-018). An existing stash ("preserve ecr comment changes") still
# modifies the now-deleted ecr.tf — do not pop/apply/drop it; popping it will
# conflict on a deleted file, which is expected. See docs/CURRENT_STATE.md.
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