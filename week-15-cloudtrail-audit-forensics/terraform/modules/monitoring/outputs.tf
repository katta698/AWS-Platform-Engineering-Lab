output "sns_topic_arn" {
  description = "ARN of the alert topic."
  value       = aws_sns_topic.alerts.arn
}

output "analyzer_function_name" {
  description = "Analyzer Lambda. Force a run instead of waiting a day: aws lambda invoke --function-name <name> out.json"
  value       = aws_lambda_function.analyzer.function_name
}

output "analyzer_log_group" {
  description = "CloudWatch log group for the analyzer."
  value       = aws_cloudwatch_log_group.analyzer.name
}

output "dlq_url" {
  description = "URL of the analyzer dead letter queue."
  value       = aws_sqs_queue.dlq.url
}

output "metric_namespace" {
  description = "CloudWatch namespace the analyzer publishes into."
  value       = var.metric_namespace
}

output "alarm_names" {
  description = <<-EOT
    Every alarm created by this module.

    All six are static thresholds -- there is deliberately no anomaly detection
    in this week. A useful side effect: nothing here creates an implicit
    CloudWatch anomaly detector, so teardown has no orphan to clean up the way
    Week 14 did.
  EOT
  value = [
    aws_cloudwatch_metric_alarm.root_usage.alarm_name,
    aws_cloudwatch_metric_alarm.login_without_mfa.alarm_name,
    aws_cloudwatch_metric_alarm.unexpected_regions.alarm_name,
    aws_cloudwatch_metric_alarm.trail_silent.alarm_name,
    aws_cloudwatch_metric_alarm.dlq_depth.alarm_name,
    aws_cloudwatch_metric_alarm.analyzer_silent.alarm_name,
  ]
}
