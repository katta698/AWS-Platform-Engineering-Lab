output "bucket_name" {
  description = "Name of the S3 storage bucket"
  value       = module.s3_storage.bucket_name
}

output "bucket_arn" {
  description = "ARN of the S3 storage bucket"
  value       = module.s3_storage.bucket_arn
}

output "sqs_queue_url" {
  description = "URL of the SQS queue receiving S3 object events"
  value       = module.cost_automation.sqs_queue_url
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for storage reports (confirm email subscription after deploy)"
  value       = module.cost_automation.sns_topic_arn
}

output "object_tagger_function_name" {
  description = "Name of the object tagger Lambda"
  value       = module.cost_automation.object_tagger_function_name
}

output "storage_reporter_function_name" {
  description = "Name of the storage cost reporter Lambda"
  value       = module.cost_automation.storage_cost_reporter_function_name
}

output "eventbridge_rule_name" {
  description = "EventBridge rule name for daily report trigger"
  value       = module.cost_automation.eventbridge_rule_name
}
