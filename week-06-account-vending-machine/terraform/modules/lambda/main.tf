###############################################################################
# Lambda Functions — webhook_receiver, account_creator, account_mover, status_notifier
###############################################################################

# ── webhook_receiver ───────────────────────────────────────────────────────────
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
      OU_IDS_JSON       = var.ou_ids_json
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

# ── account_creator ─────────────────────────────────────────────────────────────
resource "aws_lambda_function" "account_creator" {
  function_name    = "${var.project_name}-account-creator-${var.environment}"
  filename         = "${path.module}/../../../lambda/account_creator/account_creator.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../lambda/account_creator/account_creator.zip")
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = var.account_creator_role_arn
  timeout          = 30

  environment {
    variables = {
      ENVIRONMENT = var.environment
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "account_creator" {
  name              = "/aws/lambda/${aws_lambda_function.account_creator.function_name}"
  retention_in_days = 14
  tags              = var.tags
}

# ── account_mover ────────────────────────────────────────────────────────────────
resource "aws_lambda_function" "account_mover" {
  function_name    = "${var.project_name}-account-mover-${var.environment}"
  filename         = "${path.module}/../../../lambda/account_mover/account_mover.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../lambda/account_mover/account_mover.zip")
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = var.account_mover_role_arn
  timeout          = 30

  environment {
    variables = {
      ROOT_ID     = var.root_id
      ENVIRONMENT = var.environment
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "account_mover" {
  name              = "/aws/lambda/${aws_lambda_function.account_mover.function_name}"
  retention_in_days = 14
  tags              = var.tags
}

# ── status_notifier ──────────────────────────────────────────────────────────────
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
