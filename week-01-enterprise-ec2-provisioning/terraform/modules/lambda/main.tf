###############################################################################
# Module: Lambda Functions
# Three functions: servicenow_receiver, deployment_trigger, status_updater
# Uses archive_file to package Python handlers automatically
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Package Lambda zips from source ──────────────────────────────────────────
data "archive_file" "servicenow_receiver" {
  type        = "zip"
  source_file = "${path.root}/../../../lambda/servicenow_receiver/handler.py"
  output_path = "${path.module}/builds/servicenow_receiver.zip"
}

data "archive_file" "deployment_trigger" {
  type        = "zip"
  source_file = "${path.root}/../../../lambda/deployment_trigger/handler.py"
  output_path = "${path.module}/builds/deployment_trigger.zip"
}

data "archive_file" "status_updater" {
  type        = "zip"
  source_file = "${path.root}/../../../lambda/status_updater/handler.py"
  output_path = "${path.module}/builds/status_updater.zip"
}

# ── Shared assume-role policy for Lambda ─────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# ══════════════════════════════════════════════════════════════════════════════
# 1. ServiceNow Receiver Lambda
#    Triggered by API Gateway — validates HMAC, starts Step Functions execution
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_iam_role" "servicenow_receiver" {
  name               = "${var.project}-${var.environment}-sn-receiver-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "servicenow_receiver" {
  name = "sn-receiver-policy"
  role = aws_iam_role.servicenow_receiver.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StartStepFunctions"
        Effect = "Allow"
        Action = ["states:StartExecution"]
        Resource = var.state_machine_arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/${var.project}-${var.environment}-sn-receiver*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "servicenow_receiver" {
  name              = "/aws/lambda/${var.project}-${var.environment}-sn-receiver"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "servicenow_receiver" {
  function_name    = "${var.project}-${var.environment}-sn-receiver"
  role             = aws_iam_role.servicenow_receiver.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.servicenow_receiver.output_path
  source_code_hash = data.archive_file.servicenow_receiver.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      ENVIRONMENT       = var.environment
      STATE_MACHINE_ARN = var.state_machine_arn
      WEBHOOK_SECRET_PARAM = "/${var.project}/${var.environment}/webhook/secret"
    }
  }

  depends_on = [aws_cloudwatch_log_group.servicenow_receiver]
  tags       = var.tags
}

# Allow API Gateway to invoke this Lambda
resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.servicenow_receiver.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${var.api_gateway_execution_arn}/*/*"
}

# ══════════════════════════════════════════════════════════════════════════════
# 2. Deployment Trigger Lambda
#    Called by Step Functions (waitForTaskToken) — triggers GitHub Actions
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_iam_role" "deployment_trigger" {
  name               = "${var.project}-${var.environment}-deploy-trigger-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "deployment_trigger" {
  name = "deploy-trigger-policy"
  role = aws_iam_role.deployment_trigger.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSSMParams"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/${var.environment}/*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/${var.project}-${var.environment}-deploy-trigger*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "deployment_trigger" {
  name              = "/aws/lambda/${var.project}-${var.environment}-deploy-trigger"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "deployment_trigger" {
  function_name    = "${var.project}-${var.environment}-deploy-trigger"
  role             = aws_iam_role.deployment_trigger.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.deployment_trigger.output_path
  source_code_hash = data.archive_file.deployment_trigger.output_base64sha256
  timeout          = 60

  environment {
    variables = {
      ENVIRONMENT        = var.environment
      GITHUB_ORG         = var.github_org
      GITHUB_REPO        = var.github_repo
      GITHUB_TOKEN_PARAM = "/${var.project}/${var.environment}/github/token"
    }
  }

  depends_on = [aws_cloudwatch_log_group.deployment_trigger]
  tags       = var.tags
}

# ══════════════════════════════════════════════════════════════════════════════
# 3. Status Updater Lambda
#    Called by Step Functions — updates ServiceNow ticket status
# ══════════════════════════════════════════════════════════════════════════════
resource "aws_iam_role" "status_updater" {
  name               = "${var.project}-${var.environment}-status-updater-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "status_updater" {
  name = "status-updater-policy"
  role = aws_iam_role.status_updater.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSSMParams"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:*:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/${var.environment}/*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/${var.project}-${var.environment}-status-updater*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "status_updater" {
  name              = "/aws/lambda/${var.project}-${var.environment}-status-updater"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "status_updater" {
  function_name    = "${var.project}-${var.environment}-status-updater"
  role             = aws_iam_role.status_updater.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.status_updater.output_path
  source_code_hash = data.archive_file.status_updater.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      ENVIRONMENT              = var.environment
      SERVICENOW_INSTANCE_PARAM = "/${var.project}/${var.environment}/servicenow/instance_url"
      SERVICENOW_USER_PARAM    = "/${var.project}/${var.environment}/servicenow/username"
      SERVICENOW_PASS_PARAM    = "/${var.project}/${var.environment}/servicenow/password"
    }
  }

  depends_on = [aws_cloudwatch_log_group.status_updater]
  tags       = var.tags
}
