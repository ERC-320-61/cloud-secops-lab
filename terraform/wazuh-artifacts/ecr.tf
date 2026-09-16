############################################################
# Persistent private ECR repositories for the Wazuh stack images
#
# Security-account-owned (D-014). The Wazuh runtime in the Lab account pulls
# from these at a pinned version (Wazuh 4.14.7 — D-009). Cross-account pull
# permission (an ECR repository policy for the Lab account / the runtime
# instance role) is NOT added here yet — see docs/CURRENT_STATE.md "next work".
#
# image_tag_mutability = IMMUTABLE: a pushed tag cannot be overwritten.
# scan_on_push        = true:      basic vulnerability scanning on every push.
############################################################

locals {
  common_tags = {
    Project = var.project_name
    Purpose = "wazuh-artifacts"
  }

  ecr_repositories = toset([
    "wazuh-manager",
    "wazuh-indexer",
    "wazuh-dashboard",
  ])
}

resource "aws_ecr_repository" "wazuh" {
  for_each = local.ecr_repositories

  name                 = "${var.project_name}/${each.value}"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}/${each.value}"
  })
}
