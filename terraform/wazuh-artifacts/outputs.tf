############################################################
# Outputs
#
# Consumed by the B2 image-mirror workflow, the B3 artifact-publish workflow,
# and the Wazuh runtime root (terraform/wazuh-project/) once cross-account
# access is wired up.
############################################################

output "ecr_repository_urls" {
  description = "Map of Wazuh image name -> ECR repository URL (push/pull target)"
  value       = { for name, repo in aws_ecr_repository.wazuh : name => repo.repository_url }
}

output "ecr_repository_arns" {
  description = "Map of Wazuh image name -> ECR repository ARN"
  value       = { for name, repo in aws_ecr_repository.wazuh : name => repo.arn }
}

output "artifact_bucket_name" {
  description = "Name of the persistent Wazuh artifact/config bucket"
  value       = aws_s3_bucket.wazuh_artifacts.bucket
}

output "artifact_bucket_arn" {
  description = "ARN of the persistent Wazuh artifact/config bucket"
  value       = aws_s3_bucket.wazuh_artifacts.arn
}
