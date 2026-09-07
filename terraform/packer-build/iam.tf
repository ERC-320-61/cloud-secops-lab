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
# The Packer CALLER (whatever user/role eventually runs `packer build`) needs a
# separate least-privilege policy that must be reviewed before build
# authorization (PB-4). It covers: the amazon-ebs builder EC2/AMI/snapshot
# lifecycle this config actually uses; the describe/discovery calls the source
# AMI + vpc/subnet/sg filters make; `iam:PassRole` restricted to the role below;
# SSM SSH-session use via the AWS-StartSSHSession document (StartSession +
# clean TerminateSession); and `ec2:DescribeInstanceStatus` (Packer uses it
# when closing the Session Manager tunnel). It is NOT AdministratorAccess or
# `ec2:*`, and it is NOT defined here — there is no designated caller principal
# in the repo yet. See docs/RUNBOOK.md and docs/CURRENT_STATE.md (PB-4).
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
