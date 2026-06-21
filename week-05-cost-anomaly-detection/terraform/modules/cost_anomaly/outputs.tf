output "monitor_arn" {
  description = "ARN of the Cost Anomaly Monitor"
  value       = aws_ce_anomaly_monitor.this.arn
}

output "subscription_arn" {
  description = "ARN of the Cost Anomaly Subscription"
  value       = aws_ce_anomaly_subscription.this.arn
}
