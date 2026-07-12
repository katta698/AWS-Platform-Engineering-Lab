###############################################################################
# Module: Shared Application Load Balancer
# One ALB serves every self-service ticket via path-based routing
# (/<service-name>/*). Target groups and listener rules are NOT created here
# — fargate_provisioner registers them per-ticket via boto3, the same way
# Week 2 created databases imperatively instead of one-per-tenant Terraform.
# This module only owns the ALB itself and a default listener that catches
# any request that doesn't match a service's rule.
###############################################################################

resource "aws_lb" "main" {
  name                       = "${var.project_name}-${var.environment}-alb"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [var.alb_sg_id]
  subnets                    = var.public_subnet_ids
  enable_deletion_protection = false
  drop_invalid_header_fields = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-${var.environment}-alb"
  })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "No self-service route matches this path."
      status_code  = "404"
    }
  }
}
