# Runs entirely in the source account (aliased provider passed in from the
# environment). Emits structured INFO/WARN/ERROR logs on a schedule so the
# centralization + alerting layers have real multi-account traffic.

resource "aws_cloudwatch_log_group" "app" {
  name              = var.log_group_name
  retention_in_days = 14
}

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name               = "${var.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy" "logs" {
  name = "write-app-logs"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.app.arn}:*"
    }]
  })
}

resource "aws_lambda_function" "this" {
  function_name    = var.function_name
  role             = aws_iam_role.this.arn
  runtime          = "python3.13"
  handler          = "handler.lambda_handler"
  timeout          = 30
  memory_size      = 128
  filename         = "${path.module}/../../../lambda/log_generator/log_generator.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../lambda/log_generator/log_generator.zip")

  # Route the function's own stdout into the app log group instead of the
  # default /aws/lambda/* group, so one group carries the whole story.
  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.app.name
  }

  environment {
    variables = {
      LINES_PER_INVOKE = "25"
      ERROR_RATE_PCT   = "8"
    }
  }
}

resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "${var.function_name}-schedule"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule = aws_cloudwatch_event_rule.schedule.name
  arn  = aws_lambda_function.this.arn
}

resource "aws_lambda_permission" "events" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}
