variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "repository_name" {
  description = "ECR repository name (the image name)"
  type        = string
}

variable "image_retention_count" {
  description = "Number of tagged images to retain per lifecycle rule"
  type        = number
  default     = 10
}

variable "scan_on_push" {
  description = "Enable ECR basic scanning on every image push"
  type        = bool
  default     = true
}
