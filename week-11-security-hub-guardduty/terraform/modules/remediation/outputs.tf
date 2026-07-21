output "sns_topic_arn" {
  description = "SNS topic that carries remediation results and threat alerts."
  value       = aws_sns_topic.alerts.arn
}

output "dlq_url" {
  description = "URL of the remediation dead-letter queue."
  value       = aws_sqs_queue.dlq.id
}

output "dlq_arn" {
  description = "ARN of the remediation dead-letter queue."
  value       = aws_sqs_queue.dlq.arn
}

output "lambda_function_names" {
  description = "Map of the deployed remediation Lambda function names."
  value       = { for k, fn in aws_lambda_function.this : k => fn.function_name }
}

output "event_rule_names" {
  description = "Map of the EventBridge rule names routing findings to each Lambda."
  value       = { for k, r in aws_cloudwatch_event_rule.this : k => r.name }
}
