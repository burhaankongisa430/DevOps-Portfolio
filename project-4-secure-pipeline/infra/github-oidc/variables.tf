variable "project" {
  type    = string
  default = "devops-portfolio"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_org" {
  description = "GitHub username or organisation that owns the repository"
  type        = string
}

variable "github_repo" {
  description = "Repository name (without the owner prefix)"
  type        = string
  default     = "devops-portfolio"
}

variable "ecr_repository_prefix" {
  description = "ECR repository name prefix the pipeline is allowed to push to"
  type        = string
  default     = "devops-portfolio"
}
