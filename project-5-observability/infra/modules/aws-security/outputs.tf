output "guardduty_detector_id" {
  description = "GuardDuty detector ID"
  value       = aws_guardduty_detector.this.id
}

output "security_alerts_topic_arn" {
  description = "SNS topic ARN for security alerts (pass to auto-remediation module)"
  value       = aws_sns_topic.security_alerts.arn
}

output "cloudtrail_bucket" {
  description = "S3 bucket holding CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail.id
}
