############################################################
# Packer EXECUTION role (PB-4)
#
# The identity the operator assumes to run `packer build`. It is distinct from
# the builder instance role (aws_iam_role.build_ssm in iam.tf), which the
# temporary EC2 builder itself uses for SSM registration only. The two roles
# stay separate.
#
# Identity chain:
#   IAM Identity Center user
#     -> AWSReservedSSO_<operator permission set>_<rotating suffix>  (CloudGuardOperator)
#     -> sts:AssumeRole -> aws_iam_role.packer_execution (this role)
#     -> Packer amazon-ebs operations
#
# Trust uses the AWS-recommended resilient Identity Center pattern: delegate to
# the account root as principal and constrain with an ArnLike condition on
# aws:PrincipalArn matching the AWSReservedSSO role path. The generated SSO
# suffix is therefore never hard-coded and the trust survives permission-set
# re-provisioning.
#
# The AWS account ID is discovered at apply time (data.aws_caller_identity) so
# no account ID is committed to source. Single account per D-007.
#
# NOT trusted: arbitrary IAM users, AdministratorAccess, all account roles,
# external accounts.
############################################################

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  operator_sso_role_arn_pattern = "arn:aws:iam::${local.account_id}:role/aws-reserved/sso.amazonaws.com/${var.identity_center_region}/AWSReservedSSO_${var.operator_permission_set_name}_*"
}

resource "aws_iam_role" "packer_execution" {
  name        = "${var.project_name}-packer-execution-role"
  description = "Assumed by the CloudGuardOperator IAM Identity Center identity to run Packer amazon-ebs builds (PB-4)"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        AWS = "arn:aws:iam::${local.account_id}:root"
      }

      Action = "sts:AssumeRole"

      Condition = {
        ArnLike = {
          "aws:PrincipalArn" = local.operator_sso_role_arn_pattern
        }
      }
    }]
  })

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-packer-execution-role"
  })
}


############################################################
# Least-privilege inline policy
#
# Derived from packer/wazuh-ami.pkr.hcl as it stands: an EBS-backed AMI built
# from an existing VPC / subnet / security group (by filter) and an existing
# instance profile (by name), reached over SSM Session Manager. The config does
# NOT create a temporary security group, authorize public SSH ingress, use spot
# instances, use Windows, or customize KMS — so none of those permissions are
# granted.
############################################################

resource "aws_iam_role_policy" "packer_execution" {
  name = "${var.project_name}-packer-execution"
  role = aws_iam_role.packer_execution.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "Ec2ReadOnlyDiscovery"
        Effect = "Allow"

        # Source-AMI lookup, VPC/subnet/SG filter resolution, builder + AMI +
        # volume + snapshot + key-pair state polling. EC2 Describe* actions do
        # not support resource-level scoping.
        Action = [
          "ec2:DescribeImages",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceStatus",
          "ec2:DescribeRegions",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeTags",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots",
          "ec2:DescribeKeyPairs"
        ]

        Resource = "*"
      },
      {
        Sid    = "Ec2BuilderAndAmiLifecycle"
        Effect = "Allow"

        # Launch / stop / terminate the one temporary builder; create the
        # EBS-backed AMI (and its snapshots) from it; create + delete the
        # temporary SSH key pair Packer uses through the SSM tunnel; tag the
        # instance, volumes, AMI and snapshots. RunInstances and CreateImage
        # span many request resources; scoping is left to "*" (see PB-4 notes
        # in docs/CURRENT_STATE.md).
        Action = [
          "ec2:RunInstances",
          "ec2:StopInstances",
          "ec2:TerminateInstances",
          "ec2:CreateImage",
          "ec2:CreateKeyPair",
          "ec2:DeleteKeyPair",
          "ec2:CreateTags"
        ]

        Resource = "*"
      },
      {
        Sid    = "PassBuilderRoleToEc2Only"
        Effect = "Allow"

        Action   = "iam:PassRole"
        Resource = aws_iam_role.build_ssm.arn

        Condition = {
          StringEquals = {
            "iam:PassedToService" = "ec2.amazonaws.com"
          }
        }
      },
      {
        Sid    = "ReadBuilderInstanceProfile"
        Effect = "Allow"

        Action   = "iam:GetInstanceProfile"
        Resource = aws_iam_instance_profile.build_ssm.arn
      },
      {
        Sid    = "SsmInstanceReadiness"
        Effect = "Allow"

        # Packer waits for the builder's SSM agent to register before opening
        # the session; this action has no resource-level scoping.
        Action   = "ssm:DescribeInstanceInformation"
        Resource = "*"
      },
      {
        Sid    = "StartSshOverSsmSession"
        Effect = "Allow"

        Action = "ssm:StartSession"

        Resource = [
          "arn:aws:ec2:${var.aws_region}:${local.account_id}:instance/*",
          "arn:aws:ssm:${var.aws_region}::document/AWS-StartSSHSession"
        ]

        # Force IAM to verify the caller is explicitly allowed the session
        # document (defence in depth alongside the document ARN above).
        Condition = {
          BoolIfExists = {
            "ssm:SessionDocumentAccessCheck" = "true"
          }
        }
      },
      {
        Sid    = "ManageSsmSessions"
        Effect = "Allow"

        # AWS's ${aws:username} self-scoping does not populate for assumed-role
        # principals, so these are scoped to this account + region. Sessions
        # also auto-expire server-side.
        Action = [
          "ssm:TerminateSession",
          "ssm:ResumeSession"
        ]

        Resource = "arn:aws:ssm:${var.aws_region}:${local.account_id}:session/*"
      }
    ]
  })
}
