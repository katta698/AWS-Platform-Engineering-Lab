###############################################################################
# Module: Application Load Balancer
# Dev:  HTTP only (port 80 → app)
# Prod: HTTPS-only with HTTP→HTTPS redirect (set enable_https = true)
###############################################################################

# ── ALB ─────────────────────────────────────────────────────────────────────
resource "aws_lb" "main" {
  name                       = "${var.project}-${var.environment}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [var.alb_sg_id]
  subnets                    = var.public_subnet_ids
  enable_deletion_protection = var.environment == "prod" ? true : false
  drop_invalid_header_fields = true # Security best practice

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-alb"
  })
}

# ── Target Group ─────────────────────────────────────────────────────────────
resource "aws_lb_target_group" "app" {
  name                 = "${var.project}-${var.environment}-tg"
  port                 = var.app_port
  protocol             = "HTTP"
  vpc_id               = var.vpc_id
  target_type          = "instance"
  deregistration_delay = 30

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = var.health_check_path
    matcher             = "200-299"
  }

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-tg"
  })
}

# ── HTTP Listener (dev) ───────────────────────────────────────────────────────
# For dev: forwards traffic directly on port 80.
# For prod: replace this with HTTPS listener + HTTP→HTTPS redirect.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
