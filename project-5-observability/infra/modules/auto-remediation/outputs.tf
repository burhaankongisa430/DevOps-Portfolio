output "lambda_function_name" {
  description = "Auto-remediation Lambda function name"
  value       = aws_lambda_function.remediate.function_name
}

output "lambda_function_arn" {
  description = "Auto-remediation Lambda function ARN"
  value       = aws_lambda_function.remediate.arn
}

output "isolation_sg_id" {
  description = "ID of the quarantine security group (no inbound/outbound rules)"
  value       = aws_security_group.isolation.id
}
