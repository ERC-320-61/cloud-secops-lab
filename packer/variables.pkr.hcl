############################################################
# Define the AWS Region where Packer will build the Wazuh AMI
############################################################

variable "aws_region" {
  type    = string
  default = "us-east-2"
}


############################################################
# Define the temporary EC2 instance type used during the AMI build
############################################################

variable "instance_type" {
  type    = string
  default = "c5a.xlarge"
}