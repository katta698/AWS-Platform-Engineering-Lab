locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Week        = "08"
  }
}

# ── SQS ──────────────────────────────────────────────────────────────────────

resource "aws_sqs_queue" "object_events_dlq" {
  name                      = "${local.name_prefix}-object-events-dlq"
  message_retention_seconds = 1209600 # 14 days
  tags                      = local.common_tags
}

resource "aws_sqs_queue" "object_events" {
  name                       = "${local.name_prefix}-object-events"
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400 # 1 day

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.object_events_dlq.arn
    maxReceiveCount     = 3
  })

  tags = local.common_tags
}

# Allow S3 to publish to this queue
resource "aws_sqs_queue_policy" "object_events" {
  queue_url = aws_sqs_queue.object_events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowS3Send"
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.object_events.arn
      Condition = {
        ArnLike = { "aws:SourceArn" = var.bucket_arn }
      }
    }]
  })
}

# ── SNS ──────────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "storage_report" {
  name = "${local.name_prefix}-storage-report"
  tags = local.common_tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.storage_report.arn
  protocol  = "email"
  endpoint  = var.sns_email
}

# ── IAM: object_tagger Lambda ─────────────────────────────────────────────────

resource "aws_iam_role" "object_tagger" {
  name = "${local.name_prefix}-object-tagger-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "object_tagger" {
  name = "${local.name_prefix}-object-tagger-policy"
  role = aws_iam_role.object_tagger.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Tagging"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObjectTagging",
          "s3:GetObjectTagging"
        ]
        Resource = "${var.bucket_arn}/*"
      },
      {
        Sid    = "SQSConsume"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes"
        ]
        Resource = aws_sqs_queue.object_events.arn
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${local.name_prefix}-object-tagger:*"
      }
    ]
  })
}

# ── IAM: storage_cost_reporter Lambda ────────────────────────────────────────

resource "aws_iam_role" "storage_cost_reporter" {
  name = "${local.name_prefix}-storage-reporter-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "storage_cost_reporter" {
  name = "${local.name_prefix}-storage-reporter-policy"
  role = aws_iam_role.storage_cost_reporter.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3BucketInfo"
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
        ]
        Resource = "*"
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.storage_report.arn
      },
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/${local.name_prefix}-storage-reporter:*"
      }
    ]
  })
}

# ── Lambda: object_tagger ─────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "object_tagger" {
  name              = "/aws/lambda/${local.name_prefix}-object-tagger"
  retention_in_days = 14
  tags              = local.common_tags
}

data "archive_file" "object_tagger" {
  type        = "zip"
  source_file = "${path.module}/../../../lambda/object_tagger/handler.py"
  output_path = "${path.module}/../../../lambda/object_tagger/object_tagger.zip"
}

resource "aws_lambda_function" "object_tagger" {
  function_name    = "${local.name_prefix}-object-tagger"
  role             = aws_iam_role.object_tagger.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.object_tagger.output_path
  source_code_hash = data.archive_file.object_tagger.output_base64sha256
  timeout          = 60
  memory_size      = 128

  environment {
    variables = {
      BUCKET_NAME = var.bucket_name
    }
  }

  depends_on = [aws_cloudwatch_log_group.object_tagger]
  tags       = local.common_tags
}

resource "aws_lambda_event_source_mapping" "object_tagger_sqs" {
  event_source_arn = aws_sqs_queue.object_events.arn
  function_name    = aws_lambda_function.object_tagger.arn
  batch_size       = 10
}

# ── Lambda: storage_cost_reporter ─────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "storage_cost_reporter" {
  name              = "/aws/lambda/${local.name_prefix}-storage-reporter"
  retention_in_days = 14
  tags              = local.common_tags
}

data "archive_file" "storage_cost_reporter" {
  type        = "zip"
  source_file = "${path.module}/../../../lambda/storage_cost_reporter/handler.py"
  output_path = "${path.module}/../../../lambda/storage_cost_reporter/storage_cost_reporter.zip"
}

resource "aws_lambda_function" "storage_cost_reporter" {
  function_name    = "${local.name_prefix}-storage-reporter"
  role             = aws_iam_role.storage_cost_reporter.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.storage_cost_reporter.output_path
  source_code_hash = data.archive_file.storage_cost_reporter.output_base64sha256
  timeout          = 120
  memory_size      = 256

  environment {
    variables = {
      BUCKET_NAME   = var.bucket_name
      SNS_TOPIC_ARN = aws_sns_topic.storage_report.arn
      AWS_REGION_NAME = var.aws_region
    }
  }

  depends_on = [aws_cloudwatch_log_group.storage_cost_reporter]
  tags       = local.common_tags
}

# ── EventBridge: daily trigger ────────────────────────────────────────────────

resource "aws_cloudwatch_event_rule" "daily_report" {
  name                = "${local.name_prefix}-daily-storage-report"
  description         = "Triggers storage cost reporter Lambda once per day"
  schedule_expression = var.reporter_schedule
  tags                = local.common_tags
}

resource "aws_cloudwatch_event_target" "daily_report" {
  rule      = aws_cloudwatch_event_rule.daily_report.name
  target_id = "StorageCostReporter"
  arn       = aws_lambda_function.storage_cost_reporter.arn
}

resource "aws_lambda_permission" "eventbridge_invoke_reporter" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.storage_cost_reporter.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_report.arn
}

# ── CloudWatch Alarms ─────────────────────────────────────────────────────────

resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${local.name_prefix}-object-tagger-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Messages landed in object_tagger DLQ — processing failures need investigation"
  alarm_actions       = [aws_sns_topic.storage_report.arn]

  dimensions = {
    QueueName = aws_sqs_queue.object_events_dlq.name
  }

  tags = local.common_tags
}
