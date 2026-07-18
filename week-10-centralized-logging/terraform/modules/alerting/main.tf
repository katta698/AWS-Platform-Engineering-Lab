# Everything here lives in the monitoring (destination) account.

# Pre-create the destination copy of the app log group so retention is bounded
# from day one (Standard class — the metric filter below requires it; the
# Infrequent Access class permanently disables metric filters).
# VERIFY at first apply: the centralization rule consolidates into log groups
# with identical names — if it instead auto-creates the group first and this
# resource conflicts, import it (terraform import) rather than duplicating.
resource "aws_cloudwatch_log_group" "centralized" {
  name              = var.centralized_log_group_name
  retention_in_days = 30
}

# Turns ERROR-level structured log lines into a number an alarm can watch.
resource "aws_cloudwatch_log_metric_filter" "errors" {
  name           = "${var.project}-error-count"
  log_group_name = aws_cloudwatch_log_group.centralized.name
  pattern        = "{ $.level = \"ERROR\" }"

  metric_transformation {
    name          = "ErrorCount"
    namespace     = "PlatformLab/Week10"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "error_spike" {
  alarm_name          = "${var.project}-error-spike"
  alarm_description   = "ERROR volume in the centralized log stream crossed threshold"
  namespace           = "PlatformLab/Week10"
  metric_name         = "ErrorCount"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# Single pane: centralized error metric next to the SOURCE account's Lambda
# metrics — the accountId field on the second widget is what OAM enables.
resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = "${var.project}-overview"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "Centralized ERROR count (5 min)"
          region = var.aws_region
          stat   = "Sum"
          period = 300
          metrics = [
            ["PlatformLab/Week10", "ErrorCount"]
          ]
          annotations = { horizontal = [{ label = "alarm threshold", value = 5 }] }
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "Log generator invocations (source account, via OAM)"
          region = var.aws_region
          stat   = "Sum"
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", var.generator_function_name, { accountId = var.source_account_id }],
            ["AWS/Lambda", "Errors", "FunctionName", var.generator_function_name, { accountId = var.source_account_id }]
          ]
        }
      },
      {
        type = "alarm", x = 0, y = 6, width = 24, height = 3
        properties = {
          title  = "Alarm state"
          alarms = [aws_cloudwatch_metric_alarm.error_spike.arn]
        }
      }
    ]
  })
}
