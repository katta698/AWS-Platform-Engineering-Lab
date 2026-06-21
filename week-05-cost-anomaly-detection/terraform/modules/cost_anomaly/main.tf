###############################################################################
# Module: Cost Anomaly Detection
#
# Monitor    : DIMENSIONAL / SERVICE — watches all AWS services on your account
# Frequency  : IMMEDIATE — alerts fire as soon as anomaly is confirmed
# Threshold  : absolute dollar impact (default $10 above expected)
###############################################################################

# ── Monitor: watch all services ───────────────────────────────────────────────
resource "aws_ce_anomaly_monitor" "this" {
  name              = "${var.project}-${var.environment}-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
  tags              = var.tags
}

# ── Subscription: alert when anomaly exceeds threshold ────────────────────────
resource "aws_ce_anomaly_subscription" "this" {
  name      = "${var.project}-${var.environment}-subscription"
  frequency = "IMMEDIATE"

  monitor_arn_list = [aws_ce_anomaly_monitor.this.arn]

  subscriber {
    type    = "SNS"
    address = var.raw_sns_topic_arn
  }

  # Alert when actual spend is $N+ above the ML-predicted expected spend
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = [tostring(var.anomaly_threshold)]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }

  tags = var.tags
}
