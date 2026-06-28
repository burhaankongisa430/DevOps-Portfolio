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

variable "state_bucket" {
  description = "S3 bucket holding all project Terraform state"
  type        = string
}

variable "alert_email" {
  description = "Email address for security and alerting notifications"
  type        = string
  default     = "burhaankongisa@gmail.com"
}

variable "prometheus_version" {
  description = "kube-prometheus-stack Helm chart version"
  type        = string
  default     = "58.1.3"
}

variable "falco_version" {
  description = "Falco Helm chart version"
  type        = string
  default     = "4.3.0"
}
