variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "db_subnet_ids" {
  description = "Isolated DB subnet IDs for the RDS subnet group"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs to attach to the RDS instance"
  type        = list(string)
}

variable "db_name" {
  description = "Name of the initial database schema to create"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the database"
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Master password — supply via TF_VAR_db_password env var, never hardcode"
  type        = string
  sensitive   = true
}

variable "engine_version" {
  description = "PostgreSQL engine version"
  type        = string
  default     = "15.4"
}

variable "instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

variable "allocated_storage" {
  description = "Initial allocated storage in GiB"
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Upper bound for storage autoscaling in GiB (0 disables autoscaling)"
  type        = number
  default     = 100
}

variable "multi_az" {
  description = "Enable Multi-AZ standby for HA. Doubles cost — off by default for dev."
  type        = bool
  default     = false
}

variable "backup_retention_period" {
  description = "Days to retain automated backups (0 disables backups)"
  type        = number
  default     = 7
}

variable "backup_window" {
  description = "Preferred daily backup window (UTC)"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Preferred weekly maintenance window"
  type        = string
  default     = "Mon:04:00-Mon:05:00"
}

variable "deletion_protection" {
  description = "Prevent accidental deletion. Always set true for prod."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot on destroy. Set false for prod."
  type        = bool
  default     = true
}

variable "performance_insights_enabled" {
  description = "Enable Performance Insights for query-level diagnostics"
  type        = bool
  default     = false
}
