output "instance_profile_name" {
  description = "Name of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2.name
}

output "instance_profile_arn" {
  description = "ARN of the EC2 instance profile"
  value       = aws_iam_instance_profile.ec2.arn
}

output "instance_role_arn" {
  description = "ARN of the EC2 IAM role"
  value       = aws_iam_role.ec2_instance.arn
}

output "instance_role_name" {
  description = "Name of the EC2 IAM role"
  value       = aws_iam_role.ec2_instance.name
}
