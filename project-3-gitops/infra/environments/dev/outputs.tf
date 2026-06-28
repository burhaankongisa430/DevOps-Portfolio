output "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  value       = helm_release.argocd.namespace
}

output "argocd_port_forward_command" {
  description = "Command to access the ArgoCD UI locally"
  value       = "kubectl port-forward svc/argocd-server -n argocd 8080:80"
}

output "argocd_admin_password_command" {
  description = "Command to retrieve the initial ArgoCD admin password"
  value       = "kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d"
}

output "argo_rollouts_dashboard_command" {
  description = "Command to access the Argo Rollouts dashboard locally"
  value       = "kubectl port-forward svc/argo-rollouts-dashboard -n argo-rollouts 3100:3100"
}

output "cluster_name" {
  description = "EKS cluster name (passed through from P2)"
  value       = local.cluster_name
}
