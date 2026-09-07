############################################################
# Tags
#
# Packer selects these resources by a combination of deterministic tags:
#   - Project + Purpose  identify the CloudGuard packer-build lifecycle boundary
#   - a resource-specific Name  pins each lookup to exactly one resource
#
# The Name values below are also referenced verbatim by the Packer filters in
# packer/wazuh-ami.pkr.hcl -- keep them in sync. The design prefers a build
# failure over an ambiguous selection: the Packer Amazon builder errors if a
# vpc_filter / subnet_filter / security_group_filter matches more than one
# resource (subnet_filter is left without most_free / random so it cannot
# silently pick one of several).
############################################################

locals {
  purpose = "packer-build"

  name_vpc    = "${var.project_name}-packer-build-vpc"
  name_subnet = "${var.project_name}-packer-build-subnet"
  name_sg     = "${var.project_name}-packer-build-sg"

  common_tags = {
    Project = var.project_name
    Purpose = local.purpose
  }
}


############################################################
# Dedicated build VPC
#
# Persistent, isolated from the Wazuh runtime VPC. DNS support + hostnames are
# enabled so the ephemeral builder gets a public DNS name and the SSM agent
# resolves the public Systems Manager endpoints.
############################################################

resource "aws_vpc" "build" {
  cidr_block           = var.build_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = local.name_vpc
  })
}


############################################################
# Single build subnet
#
# map_public_ip_on_launch = false on purpose: the subnet does not implicitly
# make every instance public. The Packer builder explicitly opts in to a
# public IPv4 address (associate_public_ip_address = true) for that one
# ephemeral use.
############################################################

resource "aws_subnet" "build" {
  vpc_id                  = aws_vpc.build.id
  cidr_block              = var.build_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = local.name_subnet
  })
}


############################################################
# Internet Gateway
#
# Provides the temporary builder's outbound path to trusted package /
# dependency sources without a NAT Gateway. An IGW has no hourly or
# data-processing charge; only the ephemeral builder's public IPv4 is billed,
# and only while the builder exists. This is scoped to the isolated build VPC
# and does not affect D-002 (the Wazuh runtime subnet still has no IGW/NAT).
############################################################

resource "aws_internet_gateway" "build" {
  vpc_id = aws_vpc.build.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-packer-build-igw"
  })
}


############################################################
# Route table: default route to the Internet Gateway
############################################################

resource "aws_route_table" "build" {
  vpc_id = aws_vpc.build.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-packer-build-rt"
  })
}

resource "aws_route" "build_default" {
  route_table_id         = aws_route_table.build.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.build.id
}

resource "aws_route_table_association" "build" {
  subnet_id      = aws_subnet.build.id
  route_table_id = aws_route_table.build.id
}


############################################################
# Dedicated builder security group
#
# Inbound: NONE. Packer reaches the builder through AWS Systems Manager
# Session Manager (ssh_interface = "session_manager"), so no public — or any —
# inbound SSH is required. Supplying this SG to Packer also stops Packer from
# creating its own temporary security group.
#
# Outbound: limited to the practical bake requirements.
#   - TCP 443: Docker registry/repo, AWS CLI v2 installer, AWS Systems Manager,
#              and HTTPS apt mirrors.
#   - TCP 80:  Ubuntu apt package mirrors on the Canonical AWS image still
#              serve the archive over HTTP; a 443-only rule would break
#              `apt-get update`.
# DNS resolution to the Amazon-provided VPC resolver is not filtered by
# security groups, so no explicit port 53 rule is needed. An unrestricted
# all-protocol egress rule is deliberately NOT used.
############################################################

resource "aws_security_group" "build" {
  name        = local.name_sg
  description = "Packer builder: no ingress; egress limited to HTTP/HTTPS for the AMI bake"
  vpc_id      = aws_vpc.build.id

  egress {
    description = "HTTPS: Docker repo, AWS CLI v2 installer, AWS Systems Manager, HTTPS apt mirrors"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "HTTP: Ubuntu apt package mirrors on the Canonical AWS base image"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = local.name_sg
  })
}
