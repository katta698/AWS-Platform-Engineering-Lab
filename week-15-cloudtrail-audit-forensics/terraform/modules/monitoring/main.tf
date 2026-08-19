###############################################################################
# monitoring
#
# The daily analyzer, its schedule, its dead letter queue, and the alarms.
#
# EVERY ALARM HERE IS A STATIC THRESHOLD. That is the design, and it is the
# opposite of the mixed strategy Week 14 used.
#
# Week 14 measured network traffic volume, where "normal" is genuinely unknown at
# deploy time and varies by hour of day. An anomaly-detection band was the right
# tool for that, because there was a baseline worth learning.
#
# This week measures things that should not happen at all:
#
#   root account usage                 -> 0
#   console sign-in without MFA        -> 0
#   mutating activity in unused regions -> 0
#
# Handing those to anomaly detection would teach it a comfortable baseline rate
# of root logins and then stop reporting them. A metric whose correct value is a
# FACT rather than a PATTERN wants a fixed threshold. Anomaly detection would
# also cost $3.00/alarm/month against $0.10, so the wrong tool is both less
# effective and thirty times dearer.
#
# The fourth alarm is the inverse: total_events going to zero. If the trail stops
# delivering, all three security metrics drop to zero and read as excellent news.
# That alarm is what distinguishes "nothing bad happened" from "nothing arrived".
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

###############################################################################
# Notification
###############################################################################

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"

  tags = { Name = "${var.name_prefix}-alerts" }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

data "aws_iam_policy_document" "sns" {
  statement {
    sid    = "AllowCloudWatchAlarmsToPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }

    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.alerts.arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.sns.json
}

###############################################################################
# Dead letter queue
###############################################################################

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-analyzer-dlq"
  message_retention_seconds = 1209600 # 14 days
  sqs_managed_sse_enabled   = true

  tags = { Name = "${var.name_prefix}-analyzer-dlq" }
}

###############################################################################
# Analyzer Lambda
###############################################################################

data "archive_file" "analyzer" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${var.lambda_build_dir}/audit_analyzer.zip"
  excludes    = ["__pycache__", "*.pyc"]
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "analyzer" {
  name               = "${var.name_prefix}-analyzer-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "analyzer" {
  statement {
    sid    = "Logging"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
  }

  # Scoped to this workgroup. A broad athena:* would let the function run queries
  # outside the workgroup carrying the bytes-scanned ceiling -- the guardrail the
  # whole design leans on.
  statement {
    sid    = "RunAthenaQueries"
    effect = "Allow"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StopQueryExecution",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:athena:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:workgroup/${var.athena_workgroup}",
    ]
  }

  # Athena reads the table definition through Glue on the caller's behalf, so the
  # caller needs catalog read permissions despite never calling Glue itself.
  statement {
    sid    = "ReadGlueCatalog"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetDatabases",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions",
    ]
    resources = [
      "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:catalog",
      "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:database/${var.athena_database}",
      "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:table/${var.athena_database}/*",
    ]
  }

  statement {
    sid    = "ReadLogsWriteResults"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:PutObject",
      "s3:AbortMultipartUpload",
    ]
    resources = [var.results_bucket_arn, "${var.results_bucket_arn}/*"]
  }

  # PutMetricData supports no resource-level permission; the namespace condition
  # is the only available scoping.
  statement {
    sid       = "PublishMetrics"
    effect    = "Allow"
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = [var.metric_namespace]
    }
  }

  statement {
    sid       = "SendToDLQ"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }
}

resource "aws_iam_role_policy" "analyzer" {
  name   = "${var.name_prefix}-analyzer-policy"
  role   = aws_iam_role.analyzer.id
  policy = data.aws_iam_policy_document.analyzer.json
}

resource "aws_cloudwatch_log_group" "analyzer" {
  name              = "/aws/lambda/${var.name_prefix}-audit-analyzer"
  retention_in_days = 14
}

resource "aws_lambda_function" "analyzer" {
  function_name = "${var.name_prefix}-audit-analyzer"
  role          = aws_iam_role.analyzer.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  architectures = ["arm64"]

  filename         = data.archive_file.analyzer.output_path
  source_code_hash = data.archive_file.analyzer.output_base64sha256

  # Bound by Athena query latency, not compute, so the timeout is generous and
  # the memory stays small.
  timeout     = var.lambda_timeout_seconds
  memory_size = 256

  environment {
    variables = {
      ATHENA_DATABASE  = var.athena_database
      ATHENA_TABLE     = var.athena_table
      ATHENA_WORKGROUP = var.athena_workgroup
      METRIC_NAMESPACE = var.metric_namespace
      EXPECTED_REGIONS = join(",", var.expected_regions)
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  depends_on = [
    aws_iam_role_policy.analyzer,
    aws_cloudwatch_log_group.analyzer,
  ]

  tags = { Name = "${var.name_prefix}-audit-analyzer" }
}

resource "aws_lambda_function_event_invoke_config" "analyzer" {
  function_name          = aws_lambda_function.analyzer.function_name
  maximum_retry_attempts = 2
}

###############################################################################
# Schedule
###############################################################################

resource "aws_cloudwatch_event_rule" "analyzer" {
  name                = "${var.name_prefix}-analyzer-schedule"
  description         = "Daily CloudTrail audit check."
  schedule_expression = var.schedule_expression

  tags = { Name = "${var.name_prefix}-analyzer-schedule" }
}

resource "aws_cloudwatch_event_target" "analyzer" {
  rule      = aws_cloudwatch_event_rule.analyzer.name
  target_id = "audit-analyzer"
  arn       = aws_lambda_function.analyzer.arn
}

resource "aws_lambda_permission" "events" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.analyzer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.analyzer.arn
}

###############################################################################
# Alarms -- the three that should be zero
#
# period is 86400 to match the daily schedule. treat_missing_data is
# notBreaching on these three because a missing datapoint means the analyzer did
# not run, which is a different incident with its own alarm below -- firing all
# three security alarms as well would be noise pointing at the wrong cause.
###############################################################################

resource "aws_cloudwatch_metric_alarm" "root_usage" {
  alarm_name          = "${var.name_prefix}-root-account-used"
  alarm_description   = "The root account performed an action. Root cannot be constrained by IAM policy or by an SCP in its own account, so any use is worth a look. Run the root-account-usage saved query."
  namespace           = var.metric_namespace
  metric_name         = "root_events"
  statistic           = "Maximum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.name_prefix}-root-account-used" }
}

resource "aws_cloudwatch_metric_alarm" "login_without_mfa" {
  alarm_name          = "${var.name_prefix}-console-login-without-mfa"
  alarm_description   = "A successful console sign-in with no second factor. Every credential-theft path ends at this event. Run the console-login-without-mfa saved query."
  namespace           = var.metric_namespace
  metric_name         = "logins_without_mfa"
  statistic           = "Maximum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.name_prefix}-console-login-without-mfa" }
}

resource "aws_cloudwatch_metric_alarm" "unexpected_regions" {
  alarm_name          = "${var.name_prefix}-activity-in-unexpected-region"
  alarm_description   = "Something was created or changed in a region this estate does not use. Often a forgotten --region flag; sometimes not. Run the activity-in-unexpected-regions saved query."
  namespace           = var.metric_namespace
  metric_name         = "unexpected_region_events"
  statistic           = "Maximum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.name_prefix}-activity-in-unexpected-region" }
}

###############################################################################
# Alarms -- the monitoring watching itself
###############################################################################

# If the trail stops delivering, every security metric above goes to zero and
# reads as good news. This is the alarm that tells the difference.
resource "aws_cloudwatch_metric_alarm" "trail_silent" {
  alarm_name          = "${var.name_prefix}-trail-delivered-nothing"
  alarm_description   = "The organization trail delivered no events at all in the last window. Every other alarm here reads clean when this happens, so treat a zero-event day as a delivery failure until proven otherwise."
  namespace           = var.metric_namespace
  metric_name         = "total_events"
  statistic           = "Maximum"
  period              = 86400
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  # A missing datapoint IS the failure condition here, so it must breach.
  treat_missing_data = "breaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.name_prefix}-trail-delivered-nothing" }
}

resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.name_prefix}-analyzer-dlq-not-empty"
  alarm_description   = "The audit analyzer failed repeatedly and messages landed in the DLQ. The audit checks are not running until this is fixed."
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

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.name_prefix}-analyzer-dlq-not-empty" }
}

# Catches the schedule being disabled or the function deleted, where nothing ever
# fails because nothing ever runs. Window is 2 days for a daily schedule so a
# single skipped run does not page anyone.
resource "aws_cloudwatch_metric_alarm" "analyzer_silent" {
  alarm_name          = "${var.name_prefix}-analyzer-not-running"
  alarm_description   = "The audit analyzer has not reported an invocation in two days."
  namespace           = "AWS/Lambda"
  metric_name         = "Invocations"
  statistic           = "Sum"
  period              = 86400
  evaluation_periods  = 2
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    FunctionName = aws_lambda_function.analyzer.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.name_prefix}-analyzer-not-running" }
}
