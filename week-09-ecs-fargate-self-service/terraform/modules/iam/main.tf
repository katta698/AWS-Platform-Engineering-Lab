###############################################################################
# IAM Roles — task execution role (shared by every self-service task),
# webhook_receiver, fargate_provisioner, status_notifier, Step Functions.
###############################################################################

# ── ECS Task Execution Role (shared across every self-service task) ──────────
# What the ECS agent needs: pull the image, write logs. Not what the app code
# itself can do — that would be a separate per-task "task role", out of scope
# for this lab's generic self-service tasks.
resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.project_name}-task-execution-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# ── webhook_receiver role ─────────────────────────────────────────────────
resource "aws_iam_role" "webhook_receiver" {
  name = "${var.project_name}-webhook-receiver-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "webhook_receiver_basic" {
  role       = aws_iam_role.webhook_receiver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "webhook_receiver_permissions" {
  name = "${var.project_name}-webhook-receiver-permissions-${var.environment}"
  role = aws_iam_role.webhook_receiver.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StartStepFunctions"
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = [var.state_machine_arn]
      },
      {
        Sid      = "SSMParameterRead"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:*:*:parameter/${var.project_name}/${var.environment}/*"
      },
    ]
  })
}

# ── fargate_provisioner role ──────────────────────────────────────────────
# Creates the per-ticket resources: ECR repo, task definition, ECS service,
# target group, listener rule, auto-scaling target. Scoped to this project's
# name prefix and this cluster/ALB where the API supports resource-level ARNs.
resource "aws_iam_role" "fargate_provisioner" {
  name = "${var.project_name}-fargate-provisioner-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "fargate_provisioner_basic" {
  role       = aws_iam_role.fargate_provisioner.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "fargate_provisioner_permissions" {
  name = "${var.project_name}-fargate-provisioner-permissions-${var.environment}"
  role = aws_iam_role.fargate_provisioner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EcrRepoLifecycle"
        Effect = "Allow"
        Action = [
          "ecr:CreateRepository",
          "ecr:DescribeRepositories",
          "ecr:PutLifecyclePolicy",
          "ecr:PutImageScanningConfiguration",
          "ecr:SetRepositoryPolicy",
          "ecr:TagResource",
        ]
        Resource = "arn:aws:ecr:*:*:repository/${var.project_name}-*"
      },
      {
        Sid    = "EcsServiceLifecycle"
        Effect = "Allow"
        Action = [
          "ecs:RegisterTaskDefinition",
          "ecs:DeregisterTaskDefinition",
          "ecs:DescribeTaskDefinition",
          "ecs:CreateService",
          "ecs:UpdateService",
          "ecs:DescribeServices",
        ]
        Resource = "*" # RegisterTaskDefinition/DescribeTaskDefinition do not support resource-level ARNs
      },
      {
        Sid    = "EcsServiceScopedToCluster"
        Effect = "Allow"
        Action = ["ecs:CreateService", "ecs:UpdateService", "ecs:DescribeServices"]
        Resource = [
          "arn:aws:ecs:*:*:service/${var.cluster_name}/${var.project_name}-*",
        ]
      },
      {
        Sid      = "AlbTargetGroupAndRule"
        Effect   = "Allow"
        Action   = ["elasticloadbalancing:CreateTargetGroup", "elasticloadbalancing:DescribeTargetGroups", "elasticloadbalancing:DescribeRules", "elasticloadbalancing:CreateRule", "elasticloadbalancing:AddTags"]
        Resource = "*" # ELBv2 create/describe actions do not support resource-level restriction
      },
      {
        Sid      = "AutoScalingRegisterAndScale"
        Effect   = "Allow"
        Action   = ["application-autoscaling:RegisterScalableTarget", "application-autoscaling:PutScalingPolicy", "application-autoscaling:DescribeScalableTargets"]
        Resource = "*"
      },
      {
        # Application Auto Scaling needs to create its ECS service-linked
        # role the first time it's ever used against ECS in this account.
        # Without this, RegisterScalableTarget fails with "User is missing
        # the following permissions: iam:CreateServiceLinkedRole" — found via
        # a real failed Step Functions execution on Week 9 (2026-07-12), not
        # anticipated in the original design.
        Sid      = "CreateAutoScalingServiceLinkedRole"
        Effect   = "Allow"
        Action   = ["iam:CreateServiceLinkedRole"]
        Resource = "arn:aws:iam::*:role/aws-service-role/ecs.application-autoscaling.amazonaws.com/AWSServiceRoleForApplicationAutoScaling_ECSService"
        Condition = {
          StringLike = { "iam:AWSServiceName" = "ecs.application-autoscaling.amazonaws.com" }
        }
      },
      {
        Sid      = "PassExecutionRoleToEcs"
        Effect   = "Allow"
        Action   = ["iam:PassRole"]
        Resource = [aws_iam_role.ecs_task_execution.arn]
        Condition = {
          StringEquals = { "iam:PassedToService" = "ecs-tasks.amazonaws.com" }
        }
      },
      {
        Sid      = "PerServiceLogGroups"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:PutRetentionPolicy"]
        Resource = "arn:aws:logs:*:*:log-group:/ecs/${var.project_name}-*"
      },
      {
        Sid      = "SSMParameterRead"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:*:*:parameter/${var.project_name}/${var.environment}/*"
      },
    ]
  })
}

# ── status_notifier role (SSM read for ServiceNow creds) ─────────────────
resource "aws_iam_role" "status_notifier" {
  name = "${var.project_name}-status-notifier-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "status_notifier_basic" {
  role       = aws_iam_role.status_notifier.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "status_notifier_permissions" {
  name = "${var.project_name}-status-notifier-permissions-${var.environment}"
  role = aws_iam_role.status_notifier.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SSMParameterRead"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:*:*:parameter/${var.project_name}/${var.environment}/*"
      },
    ]
  })
}

# ── Step Functions execution role ─────────────────────────────────────────
resource "aws_iam_role" "step_functions" {
  name = "${var.project_name}-sfn-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "sfn_policy" {
  name = "${var.project_name}-sfn-policy-${var.environment}"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [for arn in var.lambda_arns : arn]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery", "logs:GetLogDelivery",
          "logs:UpdateLogDelivery", "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries", "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies", "logs:DescribeLogGroups",
        ]
        Resource = "*"
      }
    ]
  })
}
