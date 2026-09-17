############################################################
# Outputs
#
# Consumed by: the B2 image-mirror workflow, the B3 artifact-publish
# workflow, and terraform/wazuh-project/ (ecr_registry, artifact_bucket_name —
# for the runtime bootstrap script, D-017). ecr_repository_arns is informational
# / for B2; it is NOT needed by terraform/wazuh-project/ any more — the
# runtime's ECR-pull IAM policy now lives in terraform/wazuh-runtime-identity/
# (D-018), which builds its own repository ARNs deterministically rather than
# reading this output (see that root's iam.tf for why).
############################################################

output "ecr_repository_urls" {
  description = "Map of Wazuh image name -> ECR repository URL (push/pull target, for B2)"
  value       = { for name, repo in aws_ecr_repository.wazuh : name => repo.repository_url }
}

output "ecr_repository_arns" {
  description = "Map of Wazuh image name -> ECR repository ARN (informational / for B2)"
  value       = { for name, repo in aws_ecr_repository.wazuh : name => repo.arn }
}

output "ecr_registry" {
  description = "ECR registry hostname for this account/region (<account>.dkr.ecr.<region>.amazonaws.com) — supply to terraform/wazuh-project/ as var.wazuh_ecr_registry (docker login target). Not the same as a repository URL."
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
}

output "artifact_bucket_name" {
  description = "Name of the persistent Wazuh artifact/config bucket"
  value       = aws_s3_bucket.wazuh_artifacts.bucket
}

output "artifact_bucket_arn" {
  description = "ARN of the persistent Wazuh artifact/config bucket"
  value       = aws_s3_bucket.wazuh_artifacts.arn
}
