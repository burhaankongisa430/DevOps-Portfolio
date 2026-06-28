variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  description = "VPC ID — used to create the isolation security group"
  type        = string
}

variable "sns_topic_arn" {
  description = "SNS topic ARN for remediation notifications"
  type        = string
}
