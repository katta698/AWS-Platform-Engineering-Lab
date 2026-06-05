###############################################################################
# Lambda Functions — webhook_receiver, glue_trigger, status_updater
###############################################################################

# ── webhook_receiver ───────────────────────────────────────────────────────────
resource "aws_lambda_function" "webhook_receiver" {
  function_name    = "${var.project_name}-webhook-receiver-${var.environment}"
  filename         = "${path.module}/../../../lambda/webhook_receiver/webhook_receiver.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../lambda/webhook_receiver/webhook_receiver.zip")
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = var.lambda_role_arn
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

# ── glue_trigger ───────────────────────────────────────────────────────────────
resource "aws_lambda_function" "glue_trigger" {
  function_name    = "${var.project_name}-glue-trigger-${var.environment}"
  filename         = "${path.module}/../../../lambda/glue_trigger/glue_trigger.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../lambda/glue_trigger/glue_trigger.zip")
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = var.lambda_role_arn
  timeout          = 60

  environment {
    variables = {
      CRAWLER_NAME = var.crawler_name
      JOB_NAME     = var.etl_job_name
      ENVIRONMENT  = var.environment
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "glue_trigger" {
  name              = "/aws/lambda/${aws_lambda_function.glue_trigger.function_name}"
  retention_in_days = 14
  tags              = var.tags
}

# ── status_updater ─────────────────────────────────────────────────────────────
resource "aws_lambda_function" "status_updater" {
  function_name    = "${var.project_name}-status-updater-${var.environment}"
  filename         = "${path.module}/../../../lambda/status_updater/status_updater.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../lambda/status_updater/status_updater.zip")
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  role             = var.lambda_role_arn
  timeout          = 30

  environment {
    variables = {
      SNOW_INSTANCE_PARAM = var.snow_instance_param
      SNOW_USER_PARAM     = var.snow_user_param
      SNOW_PASSWORD_PARAM = var.snow_password_param
      ATHENA_WORKGROUP    = var.athena_workgroup_name
      ENVIRONMENT         = var.environment
    }
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "status_updater" {
  name              = "/aws/lambda/${aws_lambda_function.status_updater.function_name}"
  retention_in_days = 14
  tags              = var.tags
}
