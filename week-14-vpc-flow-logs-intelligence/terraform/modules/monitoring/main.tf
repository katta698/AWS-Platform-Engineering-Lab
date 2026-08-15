###############################################################################
# monitoring
#
# The analyzer Lambda, its schedule, its dead letter queue, and the alarms.
#
# The alarm strategy is deliberately mixed, and the split is the interesting part:
#
#   Anomaly detection  -> traffic volume, NAT egress
#     Nobody knows what "normal" is for a VPC at deploy time, and it varies by
#     hour of day. A static threshold on these is either a guess that alarms
#     constantly or a guess that never fires.
#
#   Static threshold   -> port scan candidates, DLQ depth
#     These have a correct value that is a fact rather than a pattern: zero.
#     Handing them to anomaly detection would teach it a comfortable baseline
#     rate of port scanning and then stop reporting it.
#
# Using anomaly detection for everything would be more impressive-looking, cost
# 30x more, and detect less.
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
#
# Without this, a broken analyzer and a quiet network are indistinguishable:
# both produce no alarms and no notifications. The DLQ turns "the thing that
# watches the network stopped working" into its own visible event.
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
  output_path = "${var.lambda_build_dir}/flow_analyzer.zip"
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
  # outside the workgroup that carries the bytes-scanned ceiling, which is exactly
  # the guardrail this build depends on.
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
  # caller needs catalog read permissions even though it never calls Glue itself.
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

  # Athena itself does the S3 reading and result writing under these permissions.
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

  # PutMetricData does not support resource-level permissions; the namespace
  # condition is the only available scoping and is used here.
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
  name              = "/aws/lambda/${var.name_prefix}-flow-analyzer"
  retention_in_days = 14
}

resource "aws_lambda_function" "analyzer" {
  function_name = "${var.name_prefix}-flow-analyzer"
  role          = aws_iam_role.analyzer.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  architectures = ["arm64"]

  filename         = data.archive_file.analyzer.output_path
  source_code_hash = data.archive_file.analyzer.output_base64sha256

  # Athena queries are polled synchronously. The bound is query latency, not
  # compute, so the timeout is generous while memory stays small.
  timeout     = 300
  memory_size = 256

  environment {
    variables = {
      ATHENA_DATABASE  = var.athena_database
      ATHENA_TABLE     = var.athena_table
      ATHENA_WORKGROUP = var.athena_workgroup
      METRIC_NAMESPACE = var.metric_namespace
      LOOKBACK_HOURS   = tostring(var.lookback_hours)
    }
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  depends_on = [
    aws_iam_role_policy.analyzer,
    aws_cloudwatch_log_group.analyzer,
  ]

  tags = { Name = "${var.name_prefix}-flow-analyzer" }
}

# Async invocations (which is what EventBridge produces) retry twice before the
# DLQ. Left at the default deliberately: a transient Athena throttle should not
# page anyone, but a persistent failure still surfaces.
resource "aws_lambda_function_event_invoke_config" "analyzer" {
  function_name          = aws_lambda_function.analyzer.function_name
  maximum_retry_attempts = 2
}

###############################################################################
# Schedule
###############################################################################

resource "aws_cloudwatch_event_rule" "analyzer" {
  name                = "${var.name_prefix}-analyzer-schedule"
  description         = "Hourly flow log analysis run."
  schedule_expression = var.schedule_expression

  tags = { Name = "${var.name_prefix}-analyzer-schedule" }
}

resource "aws_cloudwatch_event_target" "analyzer" {
  rule      = aws_cloudwatch_event_rule.analyzer.name
  target_id = "flow-analyzer"
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
# Alarms -- static thresholds
###############################################################################

# The analyzer failing is its own incident. Depth > 0 means at least one run
# exhausted its retries.
resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.name_prefix}-analyzer-dlq-not-empty"
  alarm_description   = "The flow analyzer failed repeatedly and messages landed in the DLQ. Network monitoring is blind until this is fixed."
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

# The analyzer not running at all. Distinct from the DLQ alarm: this catches the
# schedule being disabled or the function being deleted, where nothing ever fails
# because nothing ever runs.
resource "aws_cloudwatch_metric_alarm" "analyzer_silent" {
  alarm_name          = "${var.name_prefix}-analyzer-not-running"
  alarm_description   = "The flow analyzer has not reported a successful invocation in three hours."
  namespace           = "AWS/Lambda"
  metric_name         = "Invocations"
  statistic           = "Sum"
  period              = 3600
  evaluation_periods  = 3
  threshold           = 1
  comparison_operator = "LessThanThreshold"
  # A missing datapoint IS the failure condition here, so it must breach rather
  # than be ignored -- the default would make this alarm permanently useless.
  treat_missing_data = "breaching"

  dimensions = {
    FunctionName = aws_lambda_function.analyzer.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.name_prefix}-analyzer-not-running" }
}

# Port scanning: static, because zero is the correct value and a learned
# baseline would be an argument for tolerating it.
resource "aws_cloudwatch_metric_alarm" "port_scan" {
  alarm_name          = "${var.name_prefix}-port-scan-detected"
  alarm_description   = "One or more sources probed 20+ distinct ports and were rejected. Run the port-scan-candidates saved query for detail."
  namespace           = var.metric_namespace
  metric_name         = "scanner_count"
  statistic           = "Maximum"
  period              = 3600
  evaluation_periods  = 1
  threshold           = var.port_scan_alarm_threshold
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.name_prefix}-port-scan-detected" }
}

###############################################################################
# Alarms -- anomaly detection
#
# $3.00/alarm/month each because each bills three metrics (value, upper band,
# lower band). Prorated hourly, so a short-lived build pays cents.
#
# Both use LessThanLowerOrGreaterThanUpperThreshold. The lower bound matters more
# than it first appears: traffic collapsing to near zero is a real incident
# (something died) that an upper-bound-only alarm would never report.
###############################################################################

resource "aws_cloudwatch_metric_alarm" "traffic_anomaly" {
  count = var.enable_anomaly_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-traffic-volume-anomaly"
  alarm_description   = "Total flow log byte volume is outside its learned band -- unusually high or unusually low."
  comparison_operator = "LessThanLowerOrGreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "band"
  treat_missing_data  = "missing"

  metric_query {
    id          = "band"
    expression  = "ANOMALY_DETECTION_BAND(observed, ${var.anomaly_detection_stddev})"
    label       = "Expected byte volume"
    return_data = true
  }

  metric_query {
    id          = "observed"
    return_data = true

    metric {
      namespace   = var.metric_namespace
      metric_name = "total_bytes"
      period      = 3600
      stat        = "Maximum"
    }
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.name_prefix}-traffic-volume-anomaly" }
}

resource "aws_cloudwatch_metric_alarm" "nat_egress_anomaly" {
  count = var.enable_anomaly_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-nat-egress-anomaly"
  alarm_description   = "NAT gateway egress volume is outside its learned band. This is the billed portion of egress at $0.045/GB -- a sustained breach is a cost event, not only a traffic one."
  comparison_operator = "GreaterThanUpperThreshold"
  evaluation_periods  = 2
  threshold_metric_id = "band"
  treat_missing_data  = "missing"

  metric_query {
    id          = "band"
    expression  = "ANOMALY_DETECTION_BAND(observed, ${var.anomaly_detection_stddev})"
    label       = "Expected NAT egress"
    return_data = true
  }

  metric_query {
    id          = "observed"
    return_data = true

    metric {
      namespace   = var.metric_namespace
      metric_name = "nat_bytes"
      period      = 3600
      stat        = "Maximum"
    }
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]

  tags = { Name = "${var.name_prefix}-nat-egress-anomaly" }
}
