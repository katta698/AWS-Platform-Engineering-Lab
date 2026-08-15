output "sns_topic_arn" {
  description = "ARN of the alert topic."
  value       = aws_sns_topic.alerts.arn
}

output "analyzer_function_name" {
  description = "Name of the analyzer Lambda. Use with `aws lambda invoke` to force a run rather than waiting for the schedule."
  value       = aws_lambda_function.analyzer.function_name
}

output "analyzer_function_arn" {
  description = "ARN of the analyzer Lambda."
  value       = aws_lambda_function.analyzer.arn
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
  description = "Every alarm created, so teardown and screenshots can enumerate them."
  value = compact([
    aws_cloudwatch_metric_alarm.dlq_depth.alarm_name,
    aws_cloudwatch_metric_alarm.analyzer_silent.alarm_name,
    aws_cloudwatch_metric_alarm.port_scan.alarm_name,
    var.enable_anomaly_alarms ? aws_cloudwatch_metric_alarm.traffic_anomaly[0].alarm_name : "",
    var.enable_anomaly_alarms ? aws_cloudwatch_metric_alarm.nat_egress_anomaly[0].alarm_name : "",
  ])
}
