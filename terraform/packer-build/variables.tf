############################################################
# Project name used for AWS resource names and tags
############################################################

variable "project_name" {
  description = "Name used for AWS resource names and tags"
  type        = string
  default     = "cloud-secops-lab"
}


############################################################
# AWS Region for the Packer build network
############################################################

variable "aws_region" {
  description = "AWS Region for the Packer build network (must match the Packer build region)"
  type        = string
  default     = "us-east-2"
}


############################################################
# Availability Zone for the single build subnet
############################################################

variable "availability_zone" {
  description = "Availability Zone for the build subnet"
  type        = string
  default     = "us-east-2a"
}


############################################################
# CIDR ranges for the build network
#
# Kept deliberately small and clearly non-overlapping with the Wazuh runtime
# VPC (10.0.0.0/16). A /24 VPC with a single /24 subnet is all a lone
# ephemeral Packer builder needs.
############################################################

variable "build_vpc_cidr" {
  description = "CIDR range for the Packer build VPC (must not overlap the Wazuh runtime 10.0.0.0/16)"
  type        = string
  default     = "10.10.0.0/24"
}

variable "build_subnet_cidr" {
  description = "CIDR range for the single Packer build subnet"
  type        = string
  default     = "10.10.0.0/24"
}
