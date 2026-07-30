###############################################################################
# Reporter module -- daily compliance digest.
#
# One scheduled Lambda reads GetComplianceDetailsByConfigRule for just this
# week's 3 rules (never the account's ~300 securityhub-* rules -- that scoping
# is a deliberate design decision, not an oversight) and publishes a plain-text
# summary to SNS. Short, scheduled, stateless, a few API calls -- same
# Lambda-shape justification as every prior week.
###############################################################################

resource "aws_sns_topic" "digest" {
  name = "${var.name_prefix}-digest"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.digest.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-reporter-dlq"
  message_retention_seconds = 1209600 # 14 days -- max, so a failure is never lost
  tags                      = var.tags
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

resource "aws_iam_role" "lambda" {
  name               = "${var.name_prefix}-reporter-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name_prefix}-compliance-reporter"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_iam_role_policy" "lambda" {
  name = "${var.name_prefix}-reporter-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.lambda.arn}:*"
      },
      {
        Sid      = "ReadCompliance"
        Effect   = "Allow"
        Action   = ["config:GetComplianceDetailsByConfigRule"]
        Resource = "*"
      },
      {
        Sid      = "PublishDigest"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.digest.arn
      },
      {
        Sid      = "SendToDlq"
        Effect   = "Allow"
        Action   = ["sqs:SendMessage"]
        Resource = aws_sqs_queue.dlq.arn
      },
    ]
  })
}

# Prebuilt zip, committed -- HCP VCS runs can't build (same pattern as Week 11).
resource "aws_lambda_function" "compliance_reporter" {
  function_name    = "${var.name_prefix}-compliance-reporter"
  description      = "Daily digest of compliance status for this week's 3 Config rules"
  role             = aws_iam_role.lambda.arn
  runtime          = "python3.13"
  handler          = "handler.lambda_handler"
  timeout          = 30
  memory_size      = 128
  filename         = "${path.module}/../../../lambda/compliance_reporter/compliance_reporter.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../lambda/compliance_reporter/compliance_reporter.zip")

  environment {
    variables = {
      SNS_TOPIC_ARN     = aws_sns_topic.digest.arn
      CONFIG_RULE_NAMES = join(",", var.config_rule_names)
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda,
  ]

  tags = var.tags
}

resource "aws_cloudwatch_event_rule" "daily" {
  name                = "${var.name_prefix}-compliance-digest-daily"
  description         = "Trigger the compliance_reporter Lambda once a day"
  schedule_expression = "rate(1 day)"
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.daily.name
  target_id = "compliance_reporter"
  arn       = aws_lambda_function.compliance_reporter.arn
}

resource "aws_lambda_permission" "events" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.compliance_reporter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily.arn
}

# Reporter failing to run must itself page a human -- same pattern as Week
# 11's remediation-DLQ alarm.
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${var.name_prefix}-reporter-dlq-not-empty"
  alarm_description   = "The compliance_reporter Lambda failed and its event landed in the DLQ. Investigate."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  alarm_actions = [aws_sns_topic.digest.arn]
  ok_actions    = [aws_sns_topic.digest.arn]
  tags          = var.tags
}
