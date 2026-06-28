locals {
  name_prefix = "${var.project}-${var.environment}"
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/remediate.py"
  output_path = "${path.module}/lambda/remediate.zip"
}

# ─── Isolation security group ─────────────────────────────────────────────────
#
# A security group with no rules. An EC2 instance moved here has no inbound
# or outbound traffic — it is effectively cut off from the network.
# Isolation is fast (seconds) and reversible: restore the original SGs from
# the instance tag "OriginalSGs" to bring it back.

resource "aws_security_group" "isolation" {
  name        = "${local.name_prefix}-isolation-sg"
  description = "Quarantine: no inbound or outbound. Applied by auto-remediation Lambda."
  vpc_id      = var.vpc_id

  tags = {
    Name    = "${local.name_prefix}-isolation-sg"
    Purpose = "AutoRemediation"
  }
}

# ─── Lambda IAM role ──────────────────────────────────────────────────────────

resource "aws_iam_role" "lambda" {
  name = "${local.name_prefix}-auto-remediation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_policy" "lambda" {
  name = "${local.name_prefix}-auto-remediation-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2Isolation"
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:ModifyInstanceAttribute",
          "ec2:CreateTags",
        ]
        Resource = "*"
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [var.sns_topic_arn]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_custom" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

# ─── Lambda function ──────────────────────────────────────────────────────────

resource "aws_lambda_function" "remediate" {
  function_name    = "${local.name_prefix}-auto-remediation"
  description      = "Isolates EC2 instances when GuardDuty HIGH/CRITICAL findings fire"
  role             = aws_iam_role.lambda.arn
  handler          = "remediate.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      SNS_TOPIC_ARN   = var.sns_topic_arn
      ISOLATION_SG_ID = aws_security_group.isolation.id
    }
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${aws_lambda_function.remediate.function_name}"
  retention_in_days = 30
}

# ─── EventBridge trigger ──────────────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "guardduty_high" {
  name        = "${local.name_prefix}-guardduty-remediate"
  description = "Trigger auto-remediation for GuardDuty HIGH/CRITICAL EC2 findings"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
      resource = {
        resourceType = ["Instance"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.guardduty_high.name
  target_id = "AutoRemediationLambda"
  arn       = aws_lambda_function.remediate.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.remediate.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_high.arn
}
