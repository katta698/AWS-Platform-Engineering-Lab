output "dashboard_url"       { value = "https://console.aws.amazon.com/cloudwatch/home#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}" }
output "app_log_group_name"  { value = aws_cloudwatch_log_group.app.name }
