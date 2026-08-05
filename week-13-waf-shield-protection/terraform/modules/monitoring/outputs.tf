output "sns_topic_arn" {
  description = "SNS topic receiving this web ACL's alarms."
  value       = aws_sns_topic.alerts.arn
}

output "blocked_requests_alarm_name" {
  description = "Name of the BlockedRequests alarm."
  value       = aws_cloudwatch_metric_alarm.blocked_requests.alarm_name
}

output "counted_requests_alarm_name" {
  description = "Name of the CountedRequests alarm -- the one that matters during the Count-mode observation phase."
  value       = aws_cloudwatch_metric_alarm.counted_requests.alarm_name
}
