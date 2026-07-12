###############################################################################
# Lambda Functions — webhook_receiver, fargate_provisioner, status_notifier
###############################################################################

# ── webhook_receiver ─────────────────────────────────────────────────────
resource "aws_lambda_function" "webhook_receiver" {
  function_name    = "${var.project_name}-webhook-receiver-${var.environment}"
  filename         = "${path.module}/../../../lambda/webhook_receiver/webhook_receiver.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../lambda/webhook_receiver/webhook_receiver.zip")
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = var.webhook_receiver_role_arn
  timeout          = 30

  environment {
    variables = {
      STATE_MACHINE_ARN = var.state_machine_arn
      HMAC_SECRET_PARAM = var.hmac_secret_param
      ENVIRONMENT       = var.environment
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "webhook_receiver" {
  name              = "/aws/lambda/${aws_lambda_function.webhook_receiver.function_name}"
  retention_in_days = 14
  tags              = var.tags
}

# ── fargate_provisioner ───────────────────────────────────────────────────
resource "aws_lambda_function" "fargate_provisioner" {
  function_name    = "${var.project_name}-fargate-provisioner-${var.environment}"
  filename         = "${path.module}/../../../lambda/fargate_provisioner/fargate_provisioner.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../lambda/fargate_provisioner/fargate_provisioner.zip")
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = var.fargate_provisioner_role_arn
  timeout          = 60

  environment {
    variables = {
      PROJECT_NAME            = var.project_name
      CLUSTER_NAME            = var.cluster_name
      CLUSTER_ARN             = var.cluster_arn
      PRIVATE_SUBNET_IDS_JSON = jsonencode(var.private_subnet_ids)
      ECS_TASKS_SG_ID         = var.ecs_tasks_sg_id
      EXECUTION_ROLE_ARN      = var.ecs_task_execution_role_arn
      ALB_LISTENER_ARN        = var.alb_listener_arn
      ALB_DNS_NAME            = var.alb_dns_name
      VPC_ID                  = var.vpc_id
      ENVIRONMENT             = var.environment
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "fargate_provisioner" {
  name              = "/aws/lambda/${aws_lambda_function.fargate_provisioner.function_name}"
  retention_in_days = 14
  tags              = var.tags
}

# ── status_notifier ───────────────────────────────────────────────────────
resource "aws_lambda_function" "status_notifier" {
  function_name    = "${var.project_name}-status-notifier-${var.environment}"
  filename         = "${path.module}/../../../lambda/status_notifier/status_notifier.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../lambda/status_notifier/status_notifier.zip")
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = var.status_notifier_role_arn
  timeout          = 30

  environment {
    variables = {
      SNOW_INSTANCE_PARAM = var.snow_instance_param
      SNOW_USER_PARAM     = var.snow_user_param
      SNOW_PASSWORD_PARAM = var.snow_password_param
      ENVIRONMENT         = var.environment
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "status_notifier" {
  name              = "/aws/lambda/${aws_lambda_function.status_notifier.function_name}"
  retention_in_days = 14
  tags              = var.tags
}
