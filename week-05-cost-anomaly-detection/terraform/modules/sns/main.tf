###############################################################################
# Module: SNS
#
# Two topics:
#   raw_anomaly     — Cost Anomaly Detection publishes here (raw JSON payload)
#   formatted_alert — Lambda publishes a human-readable message here;
#                     email subscribers receive the formatted alert
###############################################################################

# ── Topic 1: Raw Anomaly ──────────────────────────────────────────────────────
resource "aws_sns_topic" "raw_anomaly" {
  name = "${var.project}-${var.environment}-raw-anomaly"
  tags = var.tags
}

# Allow Cost Anomaly Detection service to publish to this topic
resource "aws_sns_topic_policy" "raw_anomaly" {
  arn = aws_sns_topic.raw_anomaly.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCostAnomalyDetection"
        Effect = "Allow"
        Principal = {
          Service = "costalerts.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.raw_anomaly.arn
      }
    ]
  })
}

# ── Topic 2: Formatted Alert ──────────────────────────────────────────────────
resource "aws_sns_topic" "formatted_alert" {
  name = "${var.project}-${var.environment}-cost-alert"
  tags = var.tags
}

# Email subscription — subscriber must confirm via the confirmation email from AWS
resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.formatted_alert.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
