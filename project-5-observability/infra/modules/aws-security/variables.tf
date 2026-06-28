variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "alert_email" {
  description = "Email address to receive security alerts via SNS"
  type        = string
}

variable "enable_config" {
  description = "Enable AWS Config — records every resource configuration change"
  type        = bool
  default     = true
}

variable "config_s3_bucket_name" {
  description = "S3 bucket for AWS Config delivery. Defaults to auto-generated name."
  type        = string
  default     = ""
}

variable "cloudtrail_s3_bucket_name" {
  description = "S3 bucket for CloudTrail logs. Defaults to auto-generated name."
  type        = string
  default     = ""
}
