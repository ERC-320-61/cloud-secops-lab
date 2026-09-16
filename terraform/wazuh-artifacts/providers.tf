############################################################
# Provider requirements for the persistent Wazuh artifact layer
#
# Third Terraform root (docs/DECISIONS.md D-016), separate from:
#   - terraform/wazuh-project/  — disposable Wazuh runtime (Lab account)
#   - terraform/packer-build/   — persistent Packer build network (Security account)
#
# Lifecycle: PERSISTENT. This root owns the private container registry and the
# artifact/config bucket that survive between Wazuh runtime deploy -> test ->
# validate -> destroy cycles. It is NOT destroyed as part of that cycle.
#
# Account placement (D-014): applied in the SECURITY account with the
# `security-admin` permission set. The account ID is discovered at apply time
# (data.aws_caller_identity) — nothing here hard-codes an account.
#
# Scope of THIS root: the persistent ECR repositories and the S3 bucket only.
# It deliberately does NOT contain the image-mirror workflow, the Wazuh
# Compose/config artifact set, certificates, runtime bootstrap, runtime EC2, or
# any Security Hub / EventBridge integration (B2/B3 and later phases).
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
