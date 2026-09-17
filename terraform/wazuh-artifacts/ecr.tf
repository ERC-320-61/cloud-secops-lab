############################################################
# Persistent private ECR repositories for the Wazuh stack images
#
# Security-account-owned (D-014). The Wazuh runtime in the Lab account pulls
# from these at a pinned version (Wazuh 4.14.7 — D-009). Cross-account pull
# permission is the repository policy below, granted unconditionally to
# var.lab_runtime_role_arn (required — D-018; that role is created by the
# persistent terraform/wazuh-runtime-identity/ root, applied before this one).
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


############################################################
# Cross-account pull access for the Lab-account Wazuh runtime
#
# A repository (resource-based) policy is required IN ADDITION to the Lab
# runtime's own identity-based policy (terraform/wazuh-runtime-identity/iam.tf)
# — cross-account access to an ECR repository needs both sides to agree.
#
# Unconditional (D-018): var.lab_runtime_role_arn is required, and the role it
# names is created by terraform/wazuh-runtime-identity/, applied before this
# root — so this grant always has a real principal on a normal single apply.
#
# Least privilege: only the 3 read-only actions `docker compose pull` needs.
# ecr:GetAuthorizationToken is a separate, non-resource-scoped, account-local
# API — granted in terraform/wazuh-runtime-identity/iam.tf, not here.
############################################################

resource "aws_ecr_repository_policy" "lab_pull" {
  for_each = local.ecr_repositories

  repository = aws_ecr_repository.wazuh[each.value].name

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowLabRuntimePull"
        Effect = "Allow"

        Principal = {
          AWS = var.lab_runtime_role_arn
        }

        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability"
        ]
      }
    ]
  })
}
