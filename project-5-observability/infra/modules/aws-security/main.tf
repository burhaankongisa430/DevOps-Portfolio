data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
}

# ─── SNS topic for security alerts ───────────────────────────────────────────

resource "aws_sns_topic" "security_alerts" {
  name = "${local.name_prefix}-security-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ─── GuardDuty ────────────────────────────────────────────────────────────────
#
# GuardDuty is AWS's ML-based threat detection service. It analyses CloudTrail
# event logs, VPC Flow Logs, and DNS logs to detect malicious behaviour —
# credential compromise, crypto-mining, unusual API calls, port scanning.
# Cost: ~$4/month for a small account with low activity.

resource "aws_guardduty_detector" "this" {
  enable = true

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = true
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = true
        }
      }
    }
  }
}

# Route GuardDuty HIGH/CRITICAL findings to SNS immediately
resource "aws_cloudwatch_event_rule" "guardduty_findings" {
  name        = "${local.name_prefix}-guardduty-high"
  description = "Capture GuardDuty HIGH and CRITICAL severity findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_to_sns" {
  rule      = aws_cloudwatch_event_rule.guardduty_findings.name
  target_id = "SendToSNS"
  arn       = aws_sns_topic.security_alerts.arn

  input_transformer {
    input_paths = {
      severity    = "$.detail.severity"
      type        = "$.detail.type"
      description = "$.detail.description"
      region      = "$.region"
    }
    input_template = "\"GuardDuty Finding [<severity>]: <type> in <region> — <description>\""
  }
}

resource "aws_sns_topic_policy" "guardduty_publish" {
  arn = aws_sns_topic.security_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "SNS:Publish"
      Resource  = aws_sns_topic.security_alerts.arn
    }]
  })
}

# ─── Security Hub ─────────────────────────────────────────────────────────────
#
# Security Hub aggregates findings from GuardDuty, Inspector, Config, IAM
# Access Analyser, and third-party tools into one dashboard with a security
# score. The AWS Foundational Security Best Practices standard highlights the
# most impactful security controls for AWS accounts.

resource "aws_securityhub_account" "this" {}

resource "aws_securityhub_standards_subscription" "aws_foundational" {
  depends_on    = [aws_securityhub_account.this]
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
}

resource "aws_securityhub_standards_subscription" "cis" {
  depends_on    = [aws_securityhub_account.this]
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/cis-aws-foundations-benchmark/v/1.4.0"
}

# ─── CloudTrail ───────────────────────────────────────────────────────────────
#
# CloudTrail records every AWS API call — who did what, from where, when.
# It is the foundation for security investigations: without it you cannot
# determine the blast radius of a credential compromise.

resource "random_id" "trail_bucket" {
  byte_length = 4
}

locals {
  trail_bucket = var.cloudtrail_s3_bucket_name != "" ? var.cloudtrail_s3_bucket_name : "${local.name_prefix}-cloudtrail-${random_id.trail_bucket.hex}"
}

resource "aws_s3_bucket" "cloudtrail" {
  bucket = local.trail_bucket

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  bucket                  = aws_s3_bucket.cloudtrail.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id
  rule {
    id     = "expire-old-logs"
    status = "Enabled"
    expiration { days = 90 }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  bucket = aws_s3_bucket.cloudtrail.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail.arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail.arn}/AWSLogs/${local.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

resource "aws_cloudtrail" "this" {
  name                          = "${local.name_prefix}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail.id
  include_global_service_events = true
  is_multi_region_trail         = false
  enable_log_file_validation    = true

  event_selector {
    read_write_type           = "All"
    include_management_events = true
  }

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

# ─── AWS Config ───────────────────────────────────────────────────────────────
#
# Config records every resource configuration change and evaluates resources
# against compliance rules. Violations surface in Security Hub.
# Even a small account benefits from Config — it tells you what changed just
# before an incident, which is invaluable for root-cause analysis.

resource "random_id" "config_bucket" {
  byte_length = 4
}

locals {
  config_bucket = var.config_s3_bucket_name != "" ? var.config_s3_bucket_name : "${local.name_prefix}-config-${random_id.config_bucket.hex}"
}

resource "aws_s3_bucket" "config" {
  count  = var.enable_config ? 1 : 0
  bucket = local.config_bucket
}

resource "aws_s3_bucket_public_access_block" "config" {
  count                   = var.enable_config ? 1 : 0
  bucket                  = aws_s3_bucket.config[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "config" {
  count = var.enable_config ? 1 : 0
  name  = "${local.name_prefix}-config-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config" {
  count      = var.enable_config ? 1 : 0
  role       = aws_iam_role.config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_config_configuration_recorder" "this" {
  count    = var.enable_config ? 1 : 0
  name     = "${local.name_prefix}-recorder"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "this" {
  count          = var.enable_config ? 1 : 0
  name           = "${local.name_prefix}-delivery"
  s3_bucket_name = aws_s3_bucket.config[0].id
  depends_on     = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  count      = var.enable_config ? 1 : 0
  name       = aws_config_configuration_recorder.this[0].name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.this]
}

# Config managed rules — automated compliance checks
resource "aws_config_config_rule" "encrypted_volumes" {
  count      = var.enable_config ? 1 : 0
  name       = "${local.name_prefix}-encrypted-volumes"
  depends_on = [aws_config_configuration_recorder_status.this]

  source {
    owner             = "AWS"
    source_identifier = "ENCRYPTED_VOLUMES"
  }
}

resource "aws_config_config_rule" "restricted_ssh" {
  count      = var.enable_config ? 1 : 0
  name       = "${local.name_prefix}-restricted-ssh"
  depends_on = [aws_config_configuration_recorder_status.this]

  source {
    owner             = "AWS"
    source_identifier = "INCOMING_SSH_DISABLED"
  }
}

resource "aws_config_config_rule" "s3_bucket_public_read_prohibited" {
  count      = var.enable_config ? 1 : 0
  name       = "${local.name_prefix}-s3-no-public-read"
  depends_on = [aws_config_configuration_recorder_status.this]

  source {
    owner             = "AWS"
    source_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
  }
}
