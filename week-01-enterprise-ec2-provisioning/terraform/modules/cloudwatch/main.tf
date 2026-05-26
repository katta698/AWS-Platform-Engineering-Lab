###############################################################################
# Module: CloudWatch Dashboard + Alarms
# Covers: ALB, ASG, EC2 metrics, log-based alarms
###############################################################################

# ── Dashboard ─────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title       = "ALB Request Count"
          region      = var.aws_region
          period      = 60
          view        = "timeSeries"
          stat        = "Sum"
          annotations = {}
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title       = "ALB Target Response Time (p99)"
          region      = var.aws_region
          period      = 60
          view        = "timeSeries"
          stat        = "p99"
          annotations = {}
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix]
          ]
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title       = "ASG CPU Utilization"
          region      = var.aws_region
          period      = 60
          view        = "timeSeries"
          stat        = "Average"
          annotations = {}
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", var.asg_name]
          ]
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Unhealthy Host Count"
          region = var.aws_region
          period = 60
          view   = "timeSeries"
          stat   = "Maximum"
          annotations = {
            horizontal = [{ value = 1, label = "Alert threshold", color = "#ff0000" }]
          }
          metrics = [
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", var.alb_arn_suffix]
          ]
        }
      }
    ]
  })
}

# ── ALB 5xx Alarm ─────────────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project}-${var.environment}-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_description   = "ALB receiving >10 5xx errors per minute"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
}

# ── Unhealthy Hosts Alarm ─────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "${var.project}-${var.environment}-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_description   = "One or more targets are unhealthy"

  dimensions = {
    LoadBalancer = var.alb_arn_suffix
    TargetGroup  = var.target_group_arn_suffix
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]
}

# ── Log Group for App ─────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "app" {
  name              = "/app/${var.project}-${var.environment}"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

# ── Log Metric Filter: ERROR count ───────────────────────────────────────────
resource "aws_cloudwatch_log_metric_filter" "error_count" {
  name           = "${var.project}-${var.environment}-error-count"
  pattern        = "[timestamp, level=ERROR, ...]"
  log_group_name = aws_cloudwatch_log_group.app.name

  metric_transformation {
    name      = "ErrorCount"
    namespace = "${var.project}/${var.environment}"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "app_errors" {
  alarm_name          = "${var.project}-${var.environment}-app-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ErrorCount"
  namespace           = "${var.project}/${var.environment}"
  period              = 60
  statistic           = "Sum"
  threshold           = 50
  treat_missing_data  = "notBreaching"
  alarm_description   = "Application error rate is high"

  alarm_actions = [var.sns_topic_arn]
}
