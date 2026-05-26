###############################################################################
# Lambda Module — webhook_receiver + db_provisioner + status_updater
# All functions run inside the VPC private subnets to reach Aurora
###############################################################################

locals {
  name        = "${var.project}-${var.environment}"
  common_tags = merge(var.tags, { Module = "lambda" })
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Shared IAM Role ───────────────────────────────────────────────────────────
resource "aws_iam_role" "lambda" {
  name = "${local.name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "vpc_access" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "lambda_permissions" {
  name = "${local.name}-lambda-permissions"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "StepFunctions"
        Effect = "Allow"
        Action = ["states:StartExecution"]
        Resource = [var.state_machine_arn]
      },
      {
        Sid    = "SecretsManager"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:CreateSecret",
          "secretsmanager:PutSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:UpdateSecretVersionStage",
          "secretsmanager:RotateSecret",
          "secretsmanager:TagResource",
        ]
        Resource = [
          var.master_secret_arn,
          "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:/${var.project}/${var.environment}/db/*",
        ]
      },
      {
        Sid    = "SSMParameters"
        Effect = "Allow"
        Action = ["ssm:GetParameter"]
        Resource = [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/${var.project}/${var.environment}/*",
        ]
      },
      {
        Sid    = "StepFunctionsCallback"
        Effect = "Allow"
        Action = [
          "states:SendTaskSuccess",
          "states:SendTaskFailure",
        ]
        Resource = "*"
      },
      {
        Sid      = "LambdaInvokeRotation"
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = var.rotation_lambda_arn
      },
    ]
  })
}

# ── Lambda: webhook_receiver ──────────────────────────────────────────────────
data "archive_file" "webhook_receiver" {
  type        = "zip"
  source_file = "${path.module}/../../../lambda/webhook_receiver/index.py"
  output_path = "${path.module}/../../../lambda/webhook_receiver/webhook_receiver.zip"
}

resource "aws_lambda_function" "webhook_receiver" {
  function_name    = "${local.name}-webhook-receiver"
  filename         = data.archive_file.webhook_receiver.output_path
  source_code_hash = data.archive_file.webhook_receiver.output_base64sha256
  role             = aws_iam_role.lambda.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = {
      STATE_MACHINE_ARN    = var.state_machine_arn
      WEBHOOK_SECRET_PARAM = var.webhook_secret_param
    }
  }

  tags = merge(local.common_tags, { Function = "webhook-receiver" })
}

resource "aws_cloudwatch_log_group" "webhook_receiver" {
  name              = "/aws/lambda/${aws_lambda_function.webhook_receiver.function_name}"
  retention_in_days = 14
  lifecycle { ignore_changes = [retention_in_days] }
}

# ── Lambda: db_provisioner ────────────────────────────────────────────────────
data "archive_file" "db_provisioner" {
  type        = "zip"
  source_file = "${path.module}/../../../lambda/db_provisioner/index.py"
  output_path = "${path.module}/../../../lambda/db_provisioner/db_provisioner.zip"
}

resource "aws_lambda_function" "db_provisioner" {
  function_name    = "${local.name}-db-provisioner"
  filename         = data.archive_file.db_provisioner.output_path
  source_code_hash = data.archive_file.db_provisioner.output_base64sha256
  role             = aws_iam_role.lambda.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  timeout          = 120 # DB creation can take up to 2 minutes
  layers           = [var.pg8000_layer_arn]

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = {
      MASTER_SECRET_ARN   = var.master_secret_arn
      ROTATION_LAMBDA_ARN = var.rotation_lambda_arn
      PROJECT             = var.project
      ENVIRONMENT         = var.environment
      ROTATION_DAYS       = "30"
    }
  }

  tags = merge(local.common_tags, { Function = "db-provisioner" })
}

resource "aws_cloudwatch_log_group" "db_provisioner" {
  name              = "/aws/lambda/${aws_lambda_function.db_provisioner.function_name}"
  retention_in_days = 14
  lifecycle { ignore_changes = [retention_in_days] }
}

# ── Lambda: status_updater ────────────────────────────────────────────────────
data "archive_file" "status_updater" {
  type        = "zip"
  source_file = "${path.module}/../../../lambda/status_updater/index.py"
  output_path = "${path.module}/../../../lambda/status_updater/status_updater.zip"
}

resource "aws_lambda_function" "status_updater" {
  function_name    = "${local.name}-status-updater"
  filename         = data.archive_file.status_updater.output_path
  source_code_hash = data.archive_file.status_updater.output_base64sha256
  role             = aws_iam_role.lambda.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = {
      SERVICENOW_INSTANCE_PARAM = var.servicenow_instance_param
      SERVICENOW_USERNAME_PARAM = var.servicenow_username_param
      SERVICENOW_PASSWORD_PARAM = var.servicenow_password_param
    }
  }

  tags = merge(local.common_tags, { Function = "status-updater" })
}

resource "aws_cloudwatch_log_group" "status_updater" {
  name              = "/aws/lambda/${aws_lambda_function.status_updater.function_name}"
  retention_in_days = 14
  lifecycle { ignore_changes = [retention_in_days] }
}
