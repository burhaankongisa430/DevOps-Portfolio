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
  description = "S3 bucket holding all project Terraform state (the P1 bootstrap bucket)"
  type        = string
}

variable "argocd_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "6.7.3"
}

variable "argo_rollouts_version" {
  description = "Argo Rollouts Helm chart version"
  type        = string
  default     = "2.35.1"
}
