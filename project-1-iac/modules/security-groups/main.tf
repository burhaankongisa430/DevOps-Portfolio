locals {
  name_prefix = "${var.project}-${var.environment}"
}

# ALB: accepts HTTP/HTTPS from the internet; forwards to the app tier.
# No other resource should have a direct inbound rule from 0.0.0.0/0.
resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb-sg"
  description = "ALB: inbound HTTP/HTTPS from internet, outbound to app tier"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "HTTP from internet"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
    description = "HTTPS from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = { Name = "${local.name_prefix}-alb-sg" }
}

# App tier: only accepts traffic from the ALB security group — never from the internet.
# This is enforced by referencing the ALB SG ID rather than a CIDR, which means
# the rule stays correct even if the ALB's IPs change.
resource "aws_security_group" "app" {
  name        = "${local.name_prefix}-app-sg"
  description = "App: inbound from ALB SG only, outbound unrestricted for SSM/CloudWatch"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.app_port
    to_port         = var.app_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "App port from ALB only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Outbound for SSM, CloudWatch, package updates"
  }

  tags = { Name = "${local.name_prefix}-app-sg" }
}

# RDS: only accepts PostgreSQL from the app security group.
# Port 22 (SSH) is absent by design — use SSM Session Manager instead.
resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds-sg"
  description = "RDS: inbound PostgreSQL from app SG only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "PostgreSQL from app tier only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = { Name = "${local.name_prefix}-rds-sg" }
}
