variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}

variable "app_port" {
  description = "Port the application listens on (ALB forwards to this)"
  type        = number
  default     = 8080
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to reach the ALB on port 80/443"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
