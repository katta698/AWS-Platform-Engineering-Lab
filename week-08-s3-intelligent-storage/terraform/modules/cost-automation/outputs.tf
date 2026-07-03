output "sqs_queue_arn" {
  description = "ARN of the SQS queue receiving S3 object-created events"
  value       = aws_sqs_queue.object_events.arn
}

output "sqs_queue_url" {
  description = "URL of the SQS queue"
  value       = aws_sqs_queue.object_events.url
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for storage reports"
  value       = aws_sns_topic.storage_report.arn
}

output "object_tagger_function_name" {
  description = "Name of the object_tagger Lambda function"
  value       = aws_lambda_function.object_tagger.function_name
}

output "storage_cost_reporter_function_name" {
  description = "Name of the storage_cost_reporter Lambda function"
  value       = aws_lambda_function.storage_cost_reporter.function_name
}

output "eventbridge_rule_name" {
  description = "Name of the EventBridge rule triggering the daily report"
  value       = aws_cloudwatch_event_rule.daily_report.name
}
