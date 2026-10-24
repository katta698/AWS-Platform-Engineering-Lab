# Week 24 -- the service that gets broken on purpose.
#
# Adapted from week-21's module with the blue/green machinery removed: this
# week only needs something real enough to notice when it breaks. One target
# group, one service, an ALB in front.
#
# THE TWO ALARMS ARE THE EXPERIMENT
# ---------------------------------
# Both watch the same metric on the same target group. They differ only in how
# quickly they are willing to believe something is wrong:
#
#   fast     60s period,  1 datapoint   -> can fire in ~1 minute
#   typical  300s period, 2 datapoints  -> cannot fire in under 10 minutes
#
# "typical" is not a strawman. A 5-minute period with 2 datapoints to alarm is
# what most teams ship, because it is what the console nudges you toward and
# because it suppresses noise. The week measures what that costs when the
# alarm is also serving as a FIS stop condition -- the safety net that is
# supposed to halt the damage.
#
# Networking: default VPC, public subnets, no NAT. A NAT gateway at ~$0.045/hr
# would be the largest line on this lab's bill. Tasks only pull a public image.
# Production puts these in private subnets; this is a cost decision, not a
# design recommendation.

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Public HTTP in"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_security_group" "task" {
  name        = "${var.name}-task"
  description = "From the ALB only"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = var.container_port
    to_port         = var.container_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = var.tags
}

resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.alb.id]

  # The lab is torn down the same week; waiting 60s to drain a dead task just
  # makes every experiment slower to observe.
  idle_timeout = 30
  tags         = var.tags
}

resource "aws_lb_target_group" "this" {
  name        = var.name
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  # Deliberately brisk. A slow health check hides the fault from the ALB, which
  # is a different experiment -- week 21 already found that one, where a broken
  # release never fired its alarm because the health check pulled the tasks out
  # before any request reached them.
  health_check {
    path                = "/"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
  }

  deregistration_delay = 5
  tags                 = var.tags
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

data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_cloudwatch_log_group" "task" {
  name              = "/ecs/${var.name}"
  retention_in_days = 1
  tags              = var.tags
}

resource "aws_ecs_cluster" "this" {
  name = var.name

  setting {
    name  = "containerInsights"
    value = "disabled" # billed per metric; the lab reads the ALB metrics instead
  }

  tags = var.tags
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = aws_iam_role.execution.arn

  container_definitions = jsonencode([{
    name      = "app"
    image     = var.image
    essential = true
    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.task.name
        "awslogs-region"        = var.region
        "awslogs-stream-prefix" = "app"
      }
    }
  }])

  tags = var.tags
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true # no NAT; see the note at the top
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  # FIS stops tasks; ECS puts them back. Without this, a stopped task can leave
  # the service briefly below minimum and the recovery timing gets noisy.
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 200

  # FIS selects tasks by tag, and a TASK does not inherit the service's tags
  # unless told to. Without this the experiment targets nothing, reports
  # success, and the service stays up -- a green run that proved nothing,
  # which is the worst possible outcome for a chaos experiment.
  enable_ecs_managed_tags = true
  propagate_tags          = "SERVICE"

  depends_on = [aws_lb_listener.http]
  tags       = merge(var.tags, { FISTarget = var.name })
}

# ---------------------------------------------------------------------------
# The two alarms. Same metric, same target group, different patience.
#
# UnHealthyHostCount rather than 5xx: when FIS stops a task the ALB sees the
# target go away, which is the signal a real operator would watch. Counting
# 5xx would depend on traffic arriving during the window, and this lab has no
# load generator running continuously.
# ---------------------------------------------------------------------------

locals {
  alarm_dimensions = {
    TargetGroup  = aws_lb_target_group.this.arn_suffix
    LoadBalancer = aws_lb.this.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_fast" {
  alarm_name          = "${var.name}-unhealthy-fast"
  alarm_description   = "1 datapoint of 60s. Can fire about a minute after impact."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  dimensions          = local.alarm_dimensions
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_typical" {
  alarm_name          = "${var.name}-unhealthy-typical"
  alarm_description   = "2 datapoints of 300s. Cannot fire in under ten minutes."
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  statistic           = "Maximum"
  dimensions          = local.alarm_dimensions
  period              = 300
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  tags                = var.tags
}
