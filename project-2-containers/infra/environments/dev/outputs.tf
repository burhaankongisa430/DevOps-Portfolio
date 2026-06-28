output "ecr_repository_url" {
  description = "ECR URL — use this as the image name in docker build/push commands"
  value       = module.ecr.repository_url
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "kubeconfig_command" {
  description = "Run this to configure kubectl"
  value       = module.eks.kubeconfig_command
}

output "aws_lbc_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller"
  value       = module.eks.aws_lbc_role_arn
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN — needed when creating IRSA roles for app service accounts"
  value       = module.eks.oidc_provider_arn
}

output "oidc_issuer_host" {
  description = "OIDC issuer hostname — needed in IRSA trust policies"
  value       = module.eks.oidc_issuer_host
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint (consumed by downstream project Helm providers)"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate"
  value       = module.eks.cluster_certificate_authority_data
  sensitive   = true
}
