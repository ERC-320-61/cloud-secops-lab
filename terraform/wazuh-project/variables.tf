variable "project_name" {
  description   = "Name used for AWS resource tags"
  type          = string
  default       = "cloud-secops-lab"
}

# Region and AZ

variable "aws_region" {
  description   = "AWS Region for the Wazuh lab"
  type          = string
  default       = "us-east-2"
}

variable "availability_zone" {
  description   = "AZ for Wazuh Resources"
  type          = string
  default       = "us-east-2a"
}


# Networking
variable "vpc_cidr" {
  description   = "VPC CIDR"
  type          = string
  default       = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description   = "Subnet CIDR"
  type          = string
  default       = "10.0.1.0/24"
}


variable "s3_prefix" {
  description   = "Required for the VPC Endpoints"
  type          = string
  default       = "com.amazonaws.us-east-2a.s3"
}

variable "s3_vpc_endpoint_type" {
  description   = "Required for S3 gateway"
  type          = string
  default       = "Gateway"
}

variable "ssm_vpc_endpoint_type" {
  description   = "Required for SSM"
  type          = string
  default       = "Interface"
}