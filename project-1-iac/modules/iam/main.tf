locals {
  name_prefix = "${var.project}-${var.environment}"
}

resource "aws_iam_role" "ec2_instance" {
  name = "${local.name_prefix}-ec2-instance-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.name_prefix}-ec2-instance-role" }
}

# SSM Session Manager replaces SSH entirely. Instances have no port 22 open;
# access is through the AWS console or `aws ssm start-session`, authenticated
# via IAM. This is the correct zero-trust pattern for ephemeral EC2.
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Allows the CloudWatch agent running on each instance to ship metrics and logs.
resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2_instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "additional" {
  count      = length(var.additional_policy_arns)
  role       = aws_iam_role.ec2_instance.name
  policy_arn = var.additional_policy_arns[count.index]
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${local.name_prefix}-ec2-instance-profile"
  role = aws_iam_role.ec2_instance.name
}
