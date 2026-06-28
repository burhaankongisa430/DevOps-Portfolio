locals {
  name_prefix = "${var.project}-${var.environment}"
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  resolved_ami_id = var.ami_id != "" ? var.ami_id : data.aws_ami.amazon_linux_2.id

  # Bootstrap script: installs SSM agent and CloudWatch agent, then starts a
  # minimal Python HTTP server on the app port so the ALB health check passes
  # immediately. Replace this with your real application startup in production.
  default_user_data = base64encode(<<-EOF
    #!/bin/bash
    set -euo pipefail
    yum update -y
    yum install -y amazon-cloudwatch-agent amazon-ssm-agent python3

    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent

    cat > /usr/local/bin/healthcheck-server.py << 'PYEOF'
    import http.server, socketserver, os
    PORT = int(os.environ.get("APP_PORT", "8080"))
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/health":
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"ok")
            else:
                self.send_response(404)
                self.end_headers()
        def log_message(self, *args): pass
    with socketserver.TCPServer(("", PORT), Handler) as srv:
        srv.serve_forever()
    PYEOF

    nohup python3 /usr/local/bin/healthcheck-server.py &>/var/log/healthcheck-server.log &
  EOF
  )
}

resource "aws_launch_template" "this" {
  name_prefix   = "${local.name_prefix}-lt-"
  image_id      = local.resolved_ami_id
  instance_type = var.instance_type

  iam_instance_profile {
    name = var.iam_instance_profile_name
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = var.security_group_ids
    delete_on_termination       = true
  }

  monitoring {
    enabled = var.enable_monitoring
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size           = var.volume_size
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = var.user_data != "" ? var.user_data : local.default_user_data

  # IMDSv2 required: blocks SSRF-based metadata credential theft, a common
  # attack vector on public-facing EC2 workloads.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name        = "${local.name_prefix}-app"
      Project     = var.project
      Environment = var.environment
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name        = "${local.name_prefix}-app-volume"
      Project     = var.project
      Environment = var.environment
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "this" {
  name                      = "${local.name_prefix}-asg"
  vpc_zone_identifier       = var.private_subnet_ids
  target_group_arns         = var.target_group_arns
  health_check_type         = "ELB"
  health_check_grace_period = var.health_check_grace_period

  min_size         = var.min_size
  max_size         = var.max_size
  desired_capacity = var.desired_capacity

  launch_template {
    id      = aws_launch_template.this.id
    version = "$Latest"
  }

  # Rolling refresh: replaces instances with the latest launch template version
  # while keeping at least 50% healthy — zero-downtime deploys without blue/green cost.
  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-asg"
    propagate_at_launch = false
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [desired_capacity]
  }
}

# Target-tracking policy: AWS automatically adjusts capacity to keep average
# CPU near the target — simpler and more responsive than step scaling.
resource "aws_autoscaling_policy" "cpu_tracking" {
  name                   = "${local.name_prefix}-cpu-tracking"
  autoscaling_group_name = aws_autoscaling_group.this.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.scale_target_cpu
  }
}
