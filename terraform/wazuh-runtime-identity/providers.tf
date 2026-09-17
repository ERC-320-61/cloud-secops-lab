############################################################
# Provider requirements for the persistent Lab runtime identity
#
# Fourth Terraform root (docs/DECISIONS.md D-018), separate from:
#   - terraform/wazuh-project/    — disposable Wazuh runtime (Lab account)
#   - terraform/wazuh-artifacts/  — persistent ECR + S3 artifact layer (Security account)
#   - terraform/packer-build/     — persistent Packer build network (Security account)
#
# Purpose: owns ONLY the Wazuh runtime EC2's IAM role + instance profile,
# split out of terraform/wazuh-project/ specifically to break the circular
# dependency that existed between that root and terraform/wazuh-artifacts/
# (D-018). This root has NO Terraform dependency on either of them — its own
# least-privilege ECR-pull / S3-read policy is built from an explicit
# `security_account_id` variable plus a naming convention shared with
# terraform/wazuh-artifacts/, not from a live cross-root output.
#
# Lifecycle: PERSISTENT, applied in the LAB account (`lab-admin`). It is NOT
# part of the Wazuh runtime deploy -> test -> validate -> destroy cycle
# (D-006) — the role/profile survive destroying and re-deploying the
# disposable runtime in terraform/wazuh-project/, and Security's grant to it
# (terraform/wazuh-artifacts/) does not need to be re-issued each cycle.
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
