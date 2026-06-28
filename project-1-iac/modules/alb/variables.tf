variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_id" {
  description = "VPC ID for the target group"
  type        = string
}

variable "subnet_ids" {
  description = "Public subnet IDs for the ALB (must span at least 2 AZs)"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs to attach to the ALB"
  type        = list(string)
}

variable "target_group_port" {
  description = "Port the target group forwards traffic to on each instance"
  type        = number
  default     = 8080
}

variable "target_group_protocol" {
  description = "Protocol for the target group (HTTP or HTTPS)"
  type        = string
  default     = "HTTP"
}

variable "health_check_path" {
  description = "HTTP path the ALB uses to assess instance health"
  type        = string
  default     = "/health"
}

variable "health_check_healthy_threshold" {
  description = "Consecutive successes before marking an instance healthy"
  type        = number
  default     = 2
}

variable "health_check_unhealthy_threshold" {
  description = "Consecutive failures before marking an instance unhealthy"
  type        = number
  default     = 3
}

variable "deregistration_delay" {
  description = "Seconds to wait for in-flight requests before deregistering a target"
  type        = number
  default     = 30
}

variable "enable_deletion_protection" {
  description = "Prevent the ALB from being destroyed via the AWS Console or CLI"
  type        = bool
  default     = false
}

variable "access_logs_bucket" {
  description = "S3 bucket for ALB access logs — leave empty to disable"
  type        = string
  default     = ""
}
