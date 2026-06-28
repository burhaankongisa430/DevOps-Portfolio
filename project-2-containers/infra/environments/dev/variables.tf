variable "project" {
  type    = string
  default = "devops-portfolio"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "p1_state_bucket" {
  description = "S3 bucket holding Project 1's Terraform state (same bucket as our backend)"
  type        = string
}

variable "p1_state_key" {
  description = "S3 key for Project 1's dev state"
  type        = string
  default     = "dev/terraform.tfstate"
}
