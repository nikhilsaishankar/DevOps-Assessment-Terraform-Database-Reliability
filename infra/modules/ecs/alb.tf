###############################################################################
# Application Load Balancer
###############################################################################

resource "aws_lb" "this" {
  name               = substr("${local.name}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids

  enable_deletion_protection = var.enable_deletion_protection
  idle_timeout               = var.idle_timeout

  # Reject requests carrying headers the ALB cannot parse instead of forwarding
  # them to the application.
  drop_invalid_header_fields = true

  dynamic "access_logs" {
    for_each = var.enable_access_logs && var.access_logs_bucket != "" ? [1] : []

    content {
      bucket  = var.access_logs_bucket
      prefix  = local.name
      enabled = true
    }
  }

  tags = merge(local.tags, {
    Name = "${local.name}-alb"
  })
}

resource "aws_lb_target_group" "this" {
  name        = substr("${local.name}-tg", 0, 32)
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # required for Fargate (awsvpc networking)

  # Shorter than the 300s default so that rolling deployments are not dominated
  # by connection draining on a stateless HTTP service.
  deregistration_delay = 30

  health_check {
    enabled             = true
    path                = var.health_check_path
    matcher             = var.health_check_matcher
    protocol            = "HTTP"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = merge(local.tags, {
    Name = "${local.name}-tg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = var.listener_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = local.tags
}
