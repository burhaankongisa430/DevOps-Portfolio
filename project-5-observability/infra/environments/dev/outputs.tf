output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = module.aws_security.guardduty_detector_id
}

output "security_alerts_topic_arn" {
  description = "SNS topic for security alerts"
  value       = module.aws_security.security_alerts_topic_arn
}

output "isolation_sg_id" {
  description = "Quarantine security group ID"
  value       = module.auto_remediation.isolation_sg_id
}

output "grafana_access_command" {
  description = "Port-forward command to access the Grafana UI locally"
  value       = "kubectl port-forward svc/kube-prometheus-stack-grafana -n monitoring 3000:80"
}

output "prometheus_access_command" {
  description = "Port-forward command to access the Prometheus UI locally"
  value       = "kubectl port-forward svc/kube-prometheus-stack-prometheus -n monitoring 9090:9090"
}
