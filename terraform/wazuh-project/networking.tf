# 1. Create the base VPC container
resource "aws_vpc" "secops_lab_vpc" {

    cidr_block              = var.vpc_cidr
    enable_dns_support      = "true" 
    enable_dns_hostnames    = "true"

    tags = {
        Name = "sec_ops_lab"
    }
}

# 2. Create Private Subnet
resource "aws_subnet" "private_1" {
    vpc_id                  = aws_vpc.secops_lab_vpc
    cidr_block              = var.subnet_cidr
    availability_zone       = var.availability_zone
}


# 3. Create Private Route Table
resource "aws_route_table" "private_1_rt" {
    vpc_id                  = aws_vpc.secops_lab_vpc 
}