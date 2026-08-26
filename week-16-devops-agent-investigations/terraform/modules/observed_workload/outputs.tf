output "function_name" {
  description = "The processor. This is what breaks."
  value       = aws_lambda_function.processor.function_name
}

output "role_name" {
  description = "Execution role. The deliberate break detaches its config-read policy."
  value       = aws_iam_role.processor.name
}

output "config_policy_name" {
  description = "The single policy the break removes -- named so the CloudTrail event for its deletion is unambiguous."
  value       = aws_iam_role_policy.config_read.name
}

output "alarm_name" {
  description = "Fires when the processor starts failing. 5-minute period, so it recovers as soon as the workload does."
  value       = aws_cloudwatch_metric_alarm.processor_errors.alarm_name
}

output "records_bucket" {
  description = "Where successful runs write. Stops growing when the break lands, which is itself a signal."
  value       = aws_s3_bucket.records.id
}

output "log_group" {
  description = "Where the AccessDeniedException appears. The agent's primary evidence."
  value       = aws_cloudwatch_log_group.processor.name
}
