############################################################
# IAM role + instance profile for the Wazuh runtime EC2 instance (Lab)
#
# Split out of terraform/wazuh-project/ (D-018) so this identity exists BEFORE
# terraform/wazuh-artifacts/ is applied — that root's cross-account grant then
# names this role's ARN directly, in a single apply, with no re-apply needed
# once this root has run.
#
# aws_iam_role.wazuh_ec2 is the ONLY place this role is created — do not
# duplicate it in terraform/wazuh-project/, which consumes it by name/ARN via
# explicit variables instead.
############################################################

locals {
  # MUST mirror terraform/wazuh-artifacts/ecr.tf's local.ecr_repositories
  # exactly (same 3 names). Kept as a literal here (not read from that root)
  # because this root is applied first — see variables.tf security_account_id.
  ecr_repositories = toset([
    "wazuh-manager",
    "wazuh-indexer",
    "wazuh-dashboard",
  ])

  ecr_repository_arns = [
    for repo in local.ecr_repositories :
    "arn:aws:ecr:${var.aws_region}:${var.security_account_id}:repository/${var.project_name}/${repo}"
  ]

  # MUST mirror terraform/wazuh-artifacts/storage.tf's bucket-name expression
  # ("${var.project_name}-artifacts-${data.aws_caller_identity.current.account_id}").
  artifact_bucket_arn = "arn:aws:s3:::${var.project_name}-artifacts-${var.security_account_id}"
}


############################################################
# Trust policy: assumable only by EC2
############################################################

resource "aws_iam_role" "wazuh_ec2" {
  name = "${var.project_name}-wazuh-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "ec2.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name    = "${var.project_name}-wazuh-ec2-role"
    Project = var.project_name
  }
}


############################################################
# Instance profile attached to the Wazuh EC2 instance by
# terraform/wazuh-project/ (by name — see its var.wazuh_runtime_instance_profile_name)
############################################################

resource "aws_iam_instance_profile" "wazuh_ec2" {
  name = "${var.project_name}-wazuh-ec2-profile"
  role = aws_iam_role.wazuh_ec2.name
}


############################################################
# Systems Manager registration (SSM-only administration)
############################################################

resource "aws_iam_role_policy_attachment" "wazuh_ssm" {
  role       = aws_iam_role.wazuh_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


############################################################
# Cross-account ECR pull — scoped to exactly the 3 Security-owned repos
#
# ecr:GetAuthorizationToken has no resource-level scoping and is always
# account-local (it authenticates against Lab's own ECR endpoint even though
# the resulting token is then used against Security's repositories, once
# terraform/wazuh-artifacts/'s repository policy allows it) — an AWS API
# constraint, not a broadening.
############################################################

resource "aws_iam_role_policy" "wazuh_ecr_pull" {
  name = "${var.project_name}-ecr-pull"
  role = aws_iam_role.wazuh_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "ecr:GetAuthorizationToken"
        ]

        Resource = "*"
      },
      {
        Effect = "Allow"

        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage"
        ]

        Resource = local.ecr_repository_arns
      }
    ]
  })
}


############################################################
# Cross-account S3 read — scoped to the `wazuh/*` prefix only
############################################################

resource "aws_iam_role_policy" "wazuh_s3_config_read" {
  name = "${var.project_name}-s3-config-read"
  role = aws_iam_role.wazuh_ec2.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "s3:ListBucket"
        ]

        Resource = local.artifact_bucket_arn

        Condition = {
          StringLike = {
            "s3:prefix" = [
              "wazuh/*"
            ]
          }
        }
      },
      {
        Effect = "Allow"

        Action = [
          "s3:GetObject"
        ]

        Resource = "${local.artifact_bucket_arn}/wazuh/*"
      }
    ]
  })
}
