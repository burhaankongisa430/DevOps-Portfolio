variable "project" {
  description = "Project name used for resource naming and tagging"
  type        = string
  default     = "devops-portfolio"
}

variable "environment" {
  description = "Environment label applied to bootstrap resources"
  type        = string
  default     = "bootstrap"
}

variable "aws_region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "us-east-1"
}
