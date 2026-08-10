############################################################
# Create the base VPC for the Wazuh security lab
############################################################

resource "aws_vpc" "secops_lab_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "${var.project_name}-vpc"
    Project = var.project_name
  }
}


############################################################
# Create the private subnet that will host the Wazuh EC2 instance
############################################################

resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.secops_lab_vpc.id
  cidr_block        = var.subnet_cidr
  availability_zone = var.availability_zone

  tags = {
    Name    = "${var.project_name}-private-1"
    Project = var.project_name
  }
}


############################################################
# Create the private route table used by the Wazuh subnet
############################################################

resource "aws_route_table" "private_1_rt" {
  vpc_id = aws_vpc.secops_lab_vpc.id

  tags = {
    Name    = "${var.project_name}-private-rt"
    Project = var.project_name
  }
}


############################################################
# Associate the private Wazuh subnet with the private route table
############################################################

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private_1_rt.id
}