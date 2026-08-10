############################################################
# Create the IAM role that the Wazuh EC2 instance is allowed to assume
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
# Create the instance profile used to attach the Wazuh IAM role to EC2
############################################################

resource "aws_iam_instance_profile" "wazuh_ec2" {
  name = "${var.project_name}-wazuh-ec2-profile"
  role = aws_iam_role.wazuh_ec2.name
}


############################################################
# Attach the AWS-managed Systems Manager policy for private EC2 administration
############################################################

resource "aws_iam_role_policy_attachment" "wazuh_ssm" {
  role       = aws_iam_role.wazuh_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


############################################################
# Allow the Wazuh EC2 instance to authenticate to and pull images from private ECR repositories
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

        Resource = [
          aws_ecr_repository.wazuh_manager.arn,
          aws_ecr_repository.wazuh_indexer.arn,
          aws_ecr_repository.wazuh_dashboard.arn
        ]
      }
    ]
  })
}


############################################################
# Allow the Wazuh EC2 instance to read only the Wazuh configuration stored in S3
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

        Resource = aws_s3_bucket.wazuh_artifacts.arn

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

        Resource = "${aws_s3_bucket.wazuh_artifacts.arn}/wazuh/*"
      }
    ]
  })
}