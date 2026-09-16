############################################################
# Project name used for AWS resource names and tags
############################################################

variable "project_name" {
  description = "Name used for AWS resource names and tags"
  type        = string
  default     = "cloud-secops-lab"
}


############################################################
# AWS Region for the persistent Wazuh artifact layer
#
# Must match the region the Wazuh runtime and the Packer build use (us-east-2)
# so the runtime can pull images / config over regional endpoints.
############################################################

variable "aws_region" {
  description = "AWS Region for the persistent Wazuh artifact layer (ECR + artifact bucket)"
  type        = string
  default     = "us-east-2"
}
