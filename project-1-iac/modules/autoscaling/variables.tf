variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "ami_id" {
  description = "AMI ID for the launch template. Defaults to latest Amazon Linux 2 if empty."
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "security_group_ids" {
  description = "Security group IDs to attach to launched instances"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for the ASG — instances never sit in public subnets"
  type        = list(string)
}

variable "target_group_arns" {
  description = "ALB target group ARNs the ASG registers instances against"
  type        = list(string)
}

variable "iam_instance_profile_name" {
  description = "IAM instance profile name to attach (grants SSM, CloudWatch, etc.)"
  type        = string
}

variable "min_size" {
  description = "Minimum number of instances in the ASG"
  type        = number
  default     = 1
}

variable "max_size" {
  description = "Maximum number of instances in the ASG"
  type        = number
  default     = 3
}

variable "desired_capacity" {
  description = "Initial desired instance count"
  type        = number
  default     = 2
}

variable "health_check_grace_period" {
  description = "Seconds after launch before the ASG starts health checking via the ALB"
  type        = number
  default     = 120
}

variable "user_data" {
  description = "Base64-encoded user data. Leave empty to use the built-in bootstrap script."
  type        = string
  default     = ""
}

variable "enable_monitoring" {
  description = "Enable detailed (1-minute) CloudWatch monitoring on instances"
  type        = bool
  default     = true
}

variable "volume_size" {
  description = "Root EBS volume size in GiB"
  type        = number
  default     = 20
}

variable "scale_target_cpu" {
  description = "Target CPU utilisation (%) for the target-tracking scaling policy"
  type        = number
  default     = 60
}
