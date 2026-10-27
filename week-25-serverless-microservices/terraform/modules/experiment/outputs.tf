output "alarm_names" {
  value = { for k, a in aws_cloudwatch_metric_alarm.throttled : k => a.alarm_name }
}

output "dashboard_name" {
  value = aws_cloudwatch_dashboard.pool.dashboard_name
}
