###############################################################################
# Module: SNS — Alerting Topic
###############################################################################

resource "aws_sns_topic" "alerts" {
  name              = "${var.project}-${var.environment}-alerts"
  kms_master_key_id = "alias/aws/sns"  # Encryption at rest

  tags = merge(var.tags, {
    Name = "${var.project}-${var.environment}-alerts"
  })
}

# Email subscriptions
resource "aws_sns_topic_subscription" "email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

# Topic policy — allow CloudWatch to publish
resource "aws_sns_topic_policy" "default" {
  arn    = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudWatchPublish"
        Effect = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alerts.arn
      },
      {
        Sid    = "AllowLambdaPublish"
        Effect = "Allow"
        Principal = { Service = "lambda.amazonaws.com" }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}
