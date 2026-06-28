output "repository_url" {
  description = "Full ECR repository URL (used as the Docker image name)"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.this.arn
}

output "registry_id" {
  description = "AWS account ID that owns the registry"
  value       = aws_ecr_repository.this.registry_id
}
