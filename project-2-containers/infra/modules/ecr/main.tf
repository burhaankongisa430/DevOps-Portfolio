locals {
  name_prefix = "${var.project}-${var.environment}"
}

resource "aws_ecr_repository" "this" {
  name                 = "${local.name_prefix}/${var.repository_name}"
  image_tag_mutability = "MUTABLE"

  # Basic scanning catches known CVEs on push without needing ECR Enhanced.
  # Switch to ENHANCED in the Project 4 pipeline — it enables continuous re-scan.
  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = "${local.name_prefix}/${var.repository_name}" }
}

# Lifecycle policy: keep the last N tagged images and expire untagged images
# after 1 day. Without this, every Docker build push accumulates images and
# the registry grows unbounded — a common source of unexpected ECR costs.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last ${var.image_retention_count} tagged images"
        selection = {
          tagStatus   = "tagged"
          tagPrefixList = ["v", "sha-", "main"]
          countType   = "imageCountMoreThan"
          countNumber = var.image_retention_count
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = { type = "expire" }
      }
    ]
  })
}
