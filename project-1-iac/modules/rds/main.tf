locals {
  name_prefix = "${var.project}-${var.environment}"
}

resource "aws_db_subnet_group" "this" {
  name        = "${local.name_prefix}-db-subnet-group"
  description = "Isolated DB subnet group for ${local.name_prefix}"
  subnet_ids  = var.db_subnet_ids

  tags = { Name = "${local.name_prefix}-db-subnet-group" }
}

resource "aws_db_parameter_group" "this" {
  name        = "${local.name_prefix}-pg15"
  family      = "postgres15"
  description = "Custom parameter group for ${local.name_prefix}"

  # Force SSL: all connections to the DB must be encrypted in transit.
  # Plaintext database access is never acceptable, even inside a VPC.
  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  # Log queries slower than 1 second so you have the data needed to diagnose
  # performance regressions before they become production incidents.
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = { Name = "${local.name_prefix}-pg15" }
}

resource "aws_db_instance" "this" {
  identifier = "${local.name_prefix}-rds"

  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = var.security_group_ids
  parameter_group_name   = aws_db_parameter_group.this.name

  multi_az            = var.multi_az
  publicly_accessible = false

  backup_retention_period = var.backup_retention_period
  backup_window           = var.backup_window
  maintenance_window      = var.maintenance_window

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.name_prefix}-rds-final-snapshot"

  performance_insights_enabled = var.performance_insights_enabled

  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  tags = { Name = "${local.name_prefix}-rds" }
}
