output "centralized_log_group_name" {
  value = aws_cloudwatch_log_group.centralized.name
}

output "sns_topic_arn" {
  value = aws_sns_topic.alerts.arn
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.this.dashboard_name
}
