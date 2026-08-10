############################################################
# Create the S3 Gateway endpoint and associate it with the private route table
############################################################

resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = aws_vpc.secops_lab_vpc.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    aws_route_table.private_1_rt.id
  ]

  tags = {
    Name    = "${var.project_name}-s3-endpoint"
    Project = var.project_name
  }
}


############################################################
# Define the AWS services that require private Interface VPC endpoints
############################################################

locals {
  interface_services = toset([
    "ssm",         # Core Systems Manager service
    "ssmmessages", # Session Manager interactive communication
    "ec2messages", # EC2 communication with Systems Manager
    "ecr.api",     # Amazon ECR API and authentication operations
    "ecr.dkr"      # Docker image pulls from private Amazon ECR repositories
  ])
}


############################################################
# Create private Interface endpoints for Systems Manager and Amazon ECR
############################################################

resource "aws_vpc_endpoint" "interface_endpoints" {
  for_each = local.interface_services

  vpc_id              = aws_vpc.secops_lab_vpc.id
  service_name        = "com.amazonaws.${var.aws_region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_1.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name    = "${var.project_name}-${each.value}-endpoint"
    Project = var.project_name
  }
}


############################################################
# Create the security group that allows HTTPS traffic to the Interface endpoints
############################################################

resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-endpoint-sg"
  description = "Allow HTTPS from the Wazuh private subnet to VPC endpoints"
  vpc_id      = aws_vpc.secops_lab_vpc.id

  ingress {
    description = "HTTPS from private subnet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.subnet_cidr]
  }

  tags = {
    Name    = "${var.project_name}-endpoint-sg"
    Project = var.project_name
  }
}