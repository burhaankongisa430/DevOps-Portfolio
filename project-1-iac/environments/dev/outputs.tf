output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB tier)"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "Private subnet IDs (app tier)"
  value       = module.vpc.private_subnet_ids
}

output "alb_dns_name" {
  description = "ALB DNS name — the public entry point for the application"
  value       = module.alb.alb_dns_name
}

output "app_url" {
  description = "Application URL"
  value       = "http://${module.alb.alb_dns_name}"
}

output "asg_name" {
  description = "Auto Scaling Group name"
  value       = module.autoscaling.asg_name
}

output "db_endpoint" {
  description = "RDS endpoint (sensitive)"
  value       = module.rds.db_endpoint
  sensitive   = true
}

output "db_name" {
  description = "Database schema name"
  value       = module.rds.db_name
}
