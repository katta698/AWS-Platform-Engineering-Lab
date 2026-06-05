###############################################################################
# CloudWatch — Week 3 SSM Fleet Management
# Dashboard: fleet health, patch compliance, session activity, Lambda errors
# Alarms: non-compliant instances, Lambda errors, SSM agent offline
###############################################################################

data "aws_region" "current" {}

resource "aws_sns_topic" "alerts" {
  name = "${var.project}-${var.environment}-fleet-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── Alarms ────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset([
    "${var.project}-${var.environment}-webhook-receiver",
    "${var.project}-${var.environment}-fleet-onboarder",
    "${var.project}-${var.environment}-patch-orchestrator",
    "${var.project}-${var.environment}-status-updater",
  ])

  alarm_name          = "${each.key}-errors"
  alarm_description   = "Lambda errors for ${each.key}"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = each.key }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "sfn_failed" {
  alarm_name          = "${var.project}-${var.environment}-sfn-failed"
  alarm_description   = "Step Functions executions failed"
  namespace           = "AWS/States"
  metric_name         = "ExecutionsFailed"
  dimensions          = { StateMachineArn = var.state_machine_arn }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
}

# ── Dashboard ─────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "fleet" {
  dashboard_name = "${var.project}-${var.environment}-fleet-management"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# SSM Fleet Management Dashboard — ${var.project} (${var.environment})\nPatch compliance, session activity, Lambda health, Step Functions executions"
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Invocations"
          region = data.aws_region.current.name
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project}-${var.environment}-webhook-receiver"],
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project}-${var.environment}-fleet-onboarder"],
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project}-${var.environment}-patch-orchestrator"],
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project}-${var.environment}-status-updater"],
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Errors"
          region = data.aws_region.current.name
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project}-${var.environment}-webhook-receiver"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project}-${var.environment}-fleet-onboarder"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project}-${var.environment}-patch-orchestrator"],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project}-${var.environment}-status-updater"],
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 2
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Duration (ms)"
          region = data.aws_region.current.name
          view   = "timeSeries"
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project}-${var.environment}-fleet-onboarder", { stat = "p95" }],
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project}-${var.environment}-patch-orchestrator", { stat = "p95" }],
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "Step Functions Executions"
          region = data.aws_region.current.name
          view   = "timeSeries"
          metrics = [
            ["AWS/States", "ExecutionsStarted",   "StateMachineArn", var.state_machine_arn],
            ["AWS/States", "ExecutionsSucceeded", "StateMachineArn", var.state_machine_arn],
            ["AWS/States", "ExecutionsFailed",    "StateMachineArn", var.state_machine_arn],
          ]
          period = 300
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 8
        width  = 12
        height = 6
        properties = {
          title  = "SSM Session Manager Activity"
          region = data.aws_region.current.name
          view   = "timeSeries"
          metrics = [
            ["AWS/SSM-SessionManager", "SessionDuration", { stat = "Sum" }],
          ]
          period = 3600
        }
      },
      {
        type   = "log"
        x      = 0
        y      = 14
        width  = 24
        height = 6
        properties = {
          title  = "Recent Fleet Operations (Step Functions)"
          region = data.aws_region.current.name
          view   = "table"
          query  = "SOURCE '/aws/states/${var.project}-${var.environment}-fleet-management' | fields @timestamp, @message | sort @timestamp desc | limit 20"
          period = 300
        }
      }
    ]
  })
}
