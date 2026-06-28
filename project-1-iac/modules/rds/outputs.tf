output "db_instance_identifier" {
  description = "RDS instance identifier"
  value       = aws_db_instance.this.identifier
}

output "db_endpoint" {
  description = "RDS instance endpoint (host:port)"
  value       = aws_db_instance.this.endpoint
  sensitive   = true
}

output "db_host" {
  description = "RDS instance hostname"
  value       = aws_db_instance.this.address
  sensitive   = true
}

output "db_port" {
  description = "RDS instance port"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "Name of the initial database schema"
  value       = aws_db_instance.this.db_name
}

output "db_instance_arn" {
  description = "ARN of the RDS instance"
  value       = aws_db_instance.this.arn
}
