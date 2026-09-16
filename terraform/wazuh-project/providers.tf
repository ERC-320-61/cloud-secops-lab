############################################################
# Provider requirements for the disposable Wazuh runtime
#
# Account placement (docs/DECISIONS.md D-014): this root is applied in the LAB
# account, with the `lab-admin` permission set (AdministratorAccess in Lab) for
# now, or a dedicated runtime execution role later. It stays on the
# deploy -> test -> validate -> destroy cycle (D-006).
#
# The account ID is discovered at apply time (data.aws_caller_identity in
# storage.tf) — nothing here hard-codes an account.
#
# Migration note: ecr.tf and storage.tf in this root still define the ECR
# repositories and the artifact bucket. Those are SUPERSEDED by
# terraform/wazuh-artifacts/ (persistent, Security account — D-016). They are
# left here for now only because an unrelated stash ("preserve ecr comment
# changes") modifies ecr.tf and removing the file would break that stash;
# their removal, and wiring this root to consume the Security-owned AMI / ECR /
# S3 across accounts, is tracked in docs/CURRENT_STATE.md "next work".
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