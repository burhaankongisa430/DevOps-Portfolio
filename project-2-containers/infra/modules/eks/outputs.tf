output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS cluster API server endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate (used by kubectl and Helm providers)"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "cluster_version" {
  description = "Kubernetes version running on the cluster"
  value       = aws_eks_cluster.this.version
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN — use this when creating IRSA roles for other controllers"
  value       = aws_iam_openid_connect_provider.cluster.arn
}

output "oidc_issuer_host" {
  description = "OIDC issuer hostname (without https://) — used in IAM trust policies"
  value       = local.oidc_issuer_host
}

output "node_group_role_arn" {
  description = "IAM role ARN for the managed node group"
  value       = aws_iam_role.node_group.arn
}

output "aws_lbc_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller"
  value       = aws_iam_role.aws_lbc.arn
}

output "kubeconfig_command" {
  description = "Run this command to update your local kubeconfig"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.name} --name ${aws_eks_cluster.this.name}"
}
