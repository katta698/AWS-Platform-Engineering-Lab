output "sns_topic_arn"          { value = aws_sns_topic.alerts.arn }
output "dashboard_name"         { value = aws_cloudwatch_dashboard.fleet.dashboard_name }
output "cloudwatch_dashboard_url" {
  value = "https://console.aws.amazon.com/cloudwatch/home#dashboards:name=${aws_cloudwatch_dashboard.fleet.dashboard_name}"
}
