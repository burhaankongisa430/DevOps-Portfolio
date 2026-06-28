output "alb_sg_id" {
  description = "Security group ID for the Application Load Balancer"
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "Security group ID for the application EC2 tier"
  value       = aws_security_group.app.id
}

output "rds_sg_id" {
  description = "Security group ID for the RDS PostgreSQL instance"
  value       = aws_security_group.rds.id
}
