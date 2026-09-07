############################################################
# IAM identity for the temporary Packer builder instance
#
# This role is assumed by the EC2 *builder instance* (not by the human/CI
# principal that runs Packer). Its only job is to let the builder register
# with and be reached through AWS Systems Manager. AmazonSSMManagedInstanceCore
# is the minimum managed policy for Session Manager registration and is
# acceptable for Phase 1.
#
# The builder is intentionally NOT granted: EC2 provisioning, ECR/S3, Wazuh
# runtime, Security Hub / GuardDuty, or any wildcard application permissions.
#
# The Packer EXECUTION role (the identity `packer build` assumes) is a separate,
# least-privilege role defined in packer-execution-role.tf (PB-4). This builder
# role is passed to it only via `iam:PassRole` scoped to this exact ARN. The two
# roles are kept distinct.
############################################################

resource "aws_iam_role" "build_ssm" {
  name = "${var.project_name}-packer-build-ssm-role"

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

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-packer-build-ssm-role"
  })
}


############################################################
# Minimum SSM permissions for the builder to register / be reached
############################################################

resource "aws_iam_role_policy_attachment" "build_ssm_core" {
  role       = aws_iam_role.build_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


############################################################
# Instance profile attached to the temporary builder by Packer
# (deterministic name — referenced directly from packer/wazuh-ami.pkr.hcl)
############################################################

resource "aws_iam_instance_profile" "build_ssm" {
  name = "${var.project_name}-packer-build-ssm-profile"
  role = aws_iam_role.build_ssm.name

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-packer-build-ssm-profile"
  })
}
