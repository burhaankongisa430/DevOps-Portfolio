locals {
  name_prefix = "${var.project}-${var.environment}"
}

resource "aws_lb" "this" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = var.security_group_ids
  subnets            = var.subnet_ids

  enable_deletion_protection = var.enable_deletion_protection
  enable_http2               = true
  idle_timeout               = 60

  dynamic "access_logs" {
    for_each = var.access_logs_bucket != "" ? [1] : []
    content {
      bucket  = var.access_logs_bucket
      prefix  = "${local.name_prefix}-alb"
      enabled = true
    }
  }

  tags = { Name = "${local.name_prefix}-alb" }
}

# deregistration_delay is set low for dev so scale-in events resolve quickly.
# In prod, raise this to match your p99 request duration so in-flight requests
# complete before the instance is removed.
resource "aws_lb_target_group" "this" {
  name                 = "${local.name_prefix}-tg"
  port                 = var.target_group_port
  protocol             = var.target_group_protocol
  vpc_id               = var.vpc_id
  target_type          = "instance"
  deregistration_delay = var.deregistration_delay

  health_check {
    enabled             = true
    path                = var.health_check_path
    protocol            = var.target_group_protocol
    healthy_threshold   = var.health_check_healthy_threshold
    unhealthy_threshold = var.health_check_unhealthy_threshold
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = { Name = "${local.name_prefix}-tg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
