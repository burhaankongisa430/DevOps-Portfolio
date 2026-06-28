variable "project" {
  description = "Project identifier used in all resource names and tags"
  type        = string
  default     = "devops-portfolio"
}

variable "environment" {
  description = "Deployment environment label"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "db_password" {
  description = "RDS master password — supply via: export TF_VAR_db_password='...' Never commit this value."
  type        = string
  sensitive   = true
}
