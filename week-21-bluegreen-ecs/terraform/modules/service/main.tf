# Week 21 -- Blue/Green on ECS, natively.
#
# ECS has shipped its own blue/green since July 2025, with canary and linear
# added in October 2025. As of March 2026 AWS recommends it over CodeDeploy for
# new work, so there is no CodeDeploy in this build: the deployment controller
# is the service itself.
#
# What that buys, concretely: the rollback lives with the service. There is no
# second system holding an opinion about whether the deployment is healthy.

# ---------------------------------------------------------------------------
# Networking -- default VPC on purpose.
#
# A NAT gateway is about $0.045/hr plus data processing, which would be the
# largest line on this lab's bill by some margin. The tasks only need to pull a
# public image, so they sit in public subnets with a public IP and no NAT.
# In production the tasks belong in private subnets behind NAT or VPC
# endpoints; that is a cost decision here, not a design recommendation.
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# The front door. Two target groups, because blue/green means both versions are
# alive at once and traffic moves between them -- not tasks replaced in place.
# ---------------------------------------------------------------------------

resource "aws_lb" "this" {
  name               = var.name
  load_balancer_type = "application"
  subnets            = var.subnet_ids
  security_groups    = [aws_security_group.alb.id]
  tags               = var.tags
}

resource "aws_lb_target_group" "blue" {
  name        = "${var.name}-blue"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # Fargate tasks register by IP, not instance id

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = var.tags
}

resource "aws_lb_target_group" "green" {
  name        = "${var.name}-green"
  port        = var.container_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    path                = "/"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = var.tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  # The listener's own default is a dead end. All real traffic goes through the
  # RULE below, because that is the object ECS rewrites during a deployment --
  # advanced_configuration takes a listener rule ARN, not a listener ARN.
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "no rule matched"
      status_code  = "404"
    }
  }

  tags = var.tags
}

resource "aws_lb_listener_rule" "production" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }

  condition {
    path_pattern { values = ["/*"] }
  }

  tags = var.tags

  # ECS swaps this rule's target group on every deployment, so Terraform must
  # stop caring which one it points at. Without this, the next plan after a
  # green deployment shows a diff that would shift production traffic back.
  lifecycle {
    ignore_changes = [action]
  }
}

# ---------------------------------------------------------------------------
# IAM. Two roles doing different jobs.
# ---------------------------------------------------------------------------

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

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

# This is the role blue/green actually needs: ECS rewrites the listener rule
# mid-deployment, and it cannot do that with the task execution role.
resource "aws_iam_role" "infrastructure" {
  name               = "${var.name}-infrastructure"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "infrastructure" {
  role       = aws_iam_role.infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRolePolicyForLoadBalancers"
}

# ---------------------------------------------------------------------------
# The workload.
#
# busybox from ECR Public, pullable without credentials, writing its version
# into a file it then serves. "A new version" is therefore an environment
# variable change -- a new task definition revision and nothing else, which
# keeps the deployment the subject of the experiment rather than a build.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "task" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_ecs_cluster" "this" {
  name = var.name
  tags = var.tags
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  tags                     = var.tags

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = var.image
      essential = true

      # serve_root empty -> "/" returns 404 -> the 4xx alarm breaches. That is
      # how the deliberately bad version is injected, without building an image.
      command = [
        "sh", "-c",
        "mkdir -p /www && [ \"$SERVE_ROOT\" = \"yes\" ] && echo \"$VERSION\" > /www/index.html; httpd -f -p ${var.container_port} -h /www"
      ]

      environment = [
        { name = "VERSION", value = var.app_version },
        { name = "SERVE_ROOT", value = var.serve_root ? "yes" : "no" },
      ]

      portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.task.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "app"
        }
      }
    }
  ])
}

# ---------------------------------------------------------------------------
# The alarm that does the rolling back.
#
# Period and evaluation count are the whole game: the alarm has to be BREACHING
# while the bake window is still open, or the deployment completes and there is
# nothing left to roll back to. 60s and one datapoint is aggressive on purpose.
#
# Alarming on 4xx rather than 5xx because the injected fault is a missing
# document, which busybox answers with 404. Production would watch 5xx and
# latency; the mechanism being demonstrated is identical.
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${var.name}-target-4xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "HTTPCode_Target_4XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "The new version is answering with 4xx. Roll the deployment back."

  dimensions = {
    LoadBalancer = aws_lb.this.arn_suffix
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# The service. This is the week in one resource.
# ---------------------------------------------------------------------------

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  tags            = var.tags

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true # no NAT; see the note at the top
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.blue.arn
    container_name   = var.container_name
    container_port   = var.container_port

    advanced_configuration {
      alternate_target_group_arn = aws_lb_target_group.green.arn
      production_listener_rule   = aws_lb_listener_rule.production.arn
      role_arn                   = aws_iam_role.infrastructure.arn
    }
  }

  deployment_configuration {
    strategy = "BLUE_GREEN"

    # Keep the old task set alive after cutover. Rollback during this window is
    # a pointer flip; after it, it is a redeploy.
    bake_time_in_minutes = var.bake_time_in_minutes
  }

  alarms {
    enable      = true
    rollback    = true
    alarm_names = [aws_cloudwatch_metric_alarm.errors.alarm_name]
  }

  depends_on = [aws_lb_listener_rule.production]
}
