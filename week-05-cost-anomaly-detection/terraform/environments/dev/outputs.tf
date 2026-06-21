output "raw_sns_topic_arn" {
  description = "ARN of the raw anomaly SNS topic (Cost Anomaly Detection publishes here)"
  value       = module.sns.raw_topic_arn
}

output "alert_sns_topic_arn" {
  description = "ARN of the formatted alert SNS topic (Lambda publishes here, email subscribed)"
  value       = module.sns.alert_topic_arn
}

output "lambda_function_name" {
  description = "Name of the cost alerter Lambda function"
  value       = module.lambda_alerter.lambda_name
}

output "lambda_function_arn" {
  description = "ARN of the cost alerter Lambda function"
  value       = module.lambda_alerter.lambda_arn
}

output "anomaly_monitor_arn" {
  description = "ARN of the Cost Anomaly Monitor"
  value       = module.cost_anomaly.monitor_arn
}

output "anomaly_subscription_arn" {
  description = "ARN of the Cost Anomaly Subscription"
  value       = module.cost_anomaly.subscription_arn
}
