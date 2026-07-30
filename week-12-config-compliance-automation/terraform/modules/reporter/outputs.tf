output "sns_topic_arn" {
  description = "SNS topic carrying the daily compliance digest."
  value       = aws_sns_topic.digest.arn
}

output "lambda_function_name" {
  description = "Deployed compliance_reporter Lambda function name."
  value       = aws_lambda_function.compliance_reporter.function_name
}

output "event_rule_name" {
  description = "EventBridge rule name driving the daily schedule."
  value       = aws_cloudwatch_event_rule.daily.name
}

output "dlq_url" {
  description = "URL of the reporter dead-letter queue."
  value       = aws_sqs_queue.dlq.id
}
