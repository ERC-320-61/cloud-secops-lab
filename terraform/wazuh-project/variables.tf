############################################################
# Define the project name used for AWS resource names and tags
############################################################

variable "project_name" {
  description = "Name used for AWS resource names and tags"
  type        = string
  default     = "cloud-secops-lab"
}


############################################################
# Define the AWS Region where the Wazuh lab will be deployed
############################################################

variable "aws_region" {
  description = "AWS Region for the Wazuh lab"
  type        = string
  default     = "us-east-2"
}


############################################################
# Define the Availability Zone used by the private Wazuh subnet
############################################################

variable "availability_zone" {
  description = "Availability Zone for Wazuh resources"
  type        = string
  default     = "us-east-2a"
}


############################################################
# Define the CIDR range used by the Wazuh VPC
############################################################

variable "vpc_cidr" {
  description = "CIDR range for the Wazuh VPC"
  type        = string
  default     = "10.0.0.0/16"
}


############################################################
# Define the CIDR range used by the private Wazuh subnet
############################################################

variable "subnet_cidr" {
  description = "CIDR range for the private Wazuh subnet"
  type        = string
  default     = "10.0.1.0/24"
}


############################################################
# Define the Packer-built AMI used to launch the Wazuh EC2 instance
############################################################

variable "wazuh_ami_id" {
  description = "AMI built by Packer for the Wazuh EC2 instance"
  type        = string
}


############################################################
# Define the EC2 instance size used to run the Wazuh single-node stack
############################################################

variable "wazuh_instance_type" {
  description = "EC2 instance type for the Wazuh server"
  type        = string
  default     = "c5a.xlarge"
}