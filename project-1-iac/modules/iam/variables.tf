variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "additional_policy_arns" {
  description = "Extra managed policy ARNs to attach to the EC2 instance role (e.g. S3 read, Secrets Manager)"
  type        = list(string)
  default     = []
}
