###############################################################################
# Module: Lambda Alerter
#
# Subscribes to the raw anomaly SNS topic → parses the Cost Anomaly Detection
# JSON payload → publishes a human-readable alert to the formatted_alert topic
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── Package Lambda zip from source ────────────────────────────────────────────
data "archive_file" "cost_alerter" {
  type        = "zip"
  source_file = "${path.module}/../../../lambda/cost_alerter/handler.py"
  output_path = "${path.module}/builds/cost_alerter.zip"
}

# ── IAM Role ──────────────────────────────────────────────────────────────────
resource "aws_iam_role" "cost_alerter" {
  name = "${var.project}-${var.environment}-cost-alerter-role"

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

resource "aws_iam_role_policy" "cost_alerter" {
  name = "cost-alerter-policy"
  role = aws_iam_role.cost_alerter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PublishFormattedAlert"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = var.alert_sns_topic_arn
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:log-group:/aws/lambda/${var.project}-${var.environment}-cost-alerter*"
      }
    ]
  })
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "cost_alerter" {
  name              = "/aws/lambda/${var.project}-${var.environment}-cost-alerter"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ── Lambda Function ───────────────────────────────────────────────────────────
resource "aws_lambda_function" "cost_alerter" {
  function_name    = "${var.project}-${var.environment}-cost-alerter"
  role             = aws_iam_role.cost_alerter.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  filename         = data.archive_file.cost_alerter.output_path
  source_code_hash = data.archive_file.cost_alerter.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      ALERT_SNS_TOPIC_ARN = var.alert_sns_topic_arn
      ENVIRONMENT         = var.environment
    }
  }

  depends_on = [aws_cloudwatch_log_group.cost_alerter]
  tags       = var.tags
}

# ── Allow SNS to invoke Lambda ────────────────────────────────────────────────
resource "aws_lambda_permission" "allow_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost_alerter.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.raw_sns_topic_arn
}

# ── Subscribe Lambda to the raw anomaly topic ─────────────────────────────────
resource "aws_sns_topic_subscription" "lambda_trigger" {
  topic_arn = var.raw_sns_topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.cost_alerter.arn
}
