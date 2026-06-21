output "raw_topic_arn" {
  description = "ARN of the raw anomaly SNS topic"
  value       = aws_sns_topic.raw_anomaly.arn
}

output "alert_topic_arn" {
  description = "ARN of the formatted alert SNS topic"
  value       = aws_sns_topic.formatted_alert.arn
}
