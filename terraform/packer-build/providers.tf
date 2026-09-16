############################################################
# Provider requirements for the persistent Packer build network
#
# Separate Terraform root from terraform/wazuh-project/ on purpose: this
# infrastructure has a persistent lifecycle and is NOT part of the Wazuh
# runtime deploy -> test -> validate -> destroy cycle. See docs/DECISIONS.md
# D-012.
#
# Account placement (docs/DECISIONS.md D-014): this root is applied in the
# SECURITY account. Bootstrap apply uses the `security-admin` permission set
# (AdministratorAccess in Security); routine `packer build` runs assume the
# execution role from the `security` permission set (CloudGuardOperator in
# Security). The account ID is discovered at apply time
# (data.aws_caller_identity) — nothing here hard-codes an account, so the same
# code applied with `security-admin` credentials lands in Security. The legacy
# copy of this infrastructure in the Management account is retired by the
# migration sequence in docs/RUNBOOK.md, not by this code.
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
