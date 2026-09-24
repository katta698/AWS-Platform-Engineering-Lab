output "consumer_function_name" {
  value = aws_lambda_function.consumer.function_name
}

output "consumer_log_group" {
  description = "The evidence trail: a matched event appears here, an unmatched one never does"
  value       = aws_cloudwatch_log_group.consumer.name
}

output "catch_all_log_group" {
  value = aws_cloudwatch_log_group.catch_all.name
}

output "dlq_url" {
  value = aws_sqs_queue.dlq.id
}

output "orders_rule_name" {
  value = aws_cloudwatch_event_rule.orders.name
}

output "catch_all_rule_name" {
  value = aws_cloudwatch_event_rule.catch_all.name
}

output "unmatched_alarm_name" {
  description = "Metric math: catch-all MatchedEvents minus orders MatchedEvents"
  value       = aws_cloudwatch_metric_alarm.unmatched_events.alarm_name
}

output "alerts_topic_arn" {
  value = aws_sns_topic.alerts.arn
}
