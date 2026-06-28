terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = "devops-portfolio/project-1-iac"
    }
  }
}

module "vpc" {
  source = "../../modules/vpc"

  project     = var.project
  environment = var.environment

  vpc_cidr             = "10.0.0.0/16"
  public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
  db_subnet_cidrs      = ["10.0.21.0/24", "10.0.22.0/24", "10.0.23.0/24"]

  single_nat_gateway      = true
  enable_flow_logs        = true
  flow_log_retention_days = 7
}

module "security_groups" {
  source = "../../modules/security-groups"

  project     = var.project
  environment = var.environment
  vpc_id      = module.vpc.vpc_id
  app_port    = 8080
}

module "iam" {
  source = "../../modules/iam"

  project     = var.project
  environment = var.environment
}

module "alb" {
  source = "../../modules/alb"

  project     = var.project
  environment = var.environment

  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids
  security_group_ids = [module.security_groups.alb_sg_id]

  target_group_port          = 8080
  health_check_path          = "/health"
  enable_deletion_protection = false
  deregistration_delay       = 30
}

module "autoscaling" {
  source = "../../modules/autoscaling"

  project     = var.project
  environment = var.environment

  private_subnet_ids        = module.vpc.private_subnet_ids
  security_group_ids        = [module.security_groups.app_sg_id]
  target_group_arns         = [module.alb.target_group_arn]
  iam_instance_profile_name = module.iam.instance_profile_name

  instance_type    = "t3.micro"
  min_size         = 1
  max_size         = 3
  desired_capacity = 2
  scale_target_cpu = 60
}

module "rds" {
  source = "../../modules/rds"

  project     = var.project
  environment = var.environment

  db_subnet_ids      = module.vpc.db_subnet_ids
  security_group_ids = [module.security_groups.rds_sg_id]

  db_name     = "appdb"
  db_username = "dbadmin"
  db_password = var.db_password

  instance_class               = "db.t3.micro"
  multi_az                     = false
  deletion_protection          = false
  skip_final_snapshot          = true
  performance_insights_enabled = false
}

# Budget alarm: alert at 80% of $50/month to avoid surprise bills.
# Estimated monthly cost for this dev stack: ~$40-45 USD.
resource "aws_budgets_budget" "dev" {
  name         = "${var.project}-${var.environment}-monthly"
  budget_type  = "COST"
  limit_amount = "50"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = ["burhaankongisa@gmail.com"]
  }
}
