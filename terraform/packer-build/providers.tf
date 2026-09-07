############################################################
# Provider requirements for the persistent Packer build network
#
# Separate Terraform root from terraform/wazuh-project/ on purpose: this
# infrastructure has a persistent lifecycle and is NOT part of the Wazuh
# runtime deploy -> test -> validate -> destroy cycle. See docs/DECISIONS.md
# D-012.
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
