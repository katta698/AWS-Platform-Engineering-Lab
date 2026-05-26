output "cluster_endpoint" {
  description = "Writer endpoint — use for all write operations"
  value       = aws_rds_cluster.main.endpoint
}

output "cluster_reader_endpoint" {
  description = "Reader endpoint — load-balanced across all reader instances"
  value       = aws_rds_cluster.main.reader_endpoint
}

output "cluster_identifier" {
  value = aws_rds_cluster.main.cluster_identifier
}

output "cluster_arn" {
  value = aws_rds_cluster.main.arn
}

output "cluster_port" {
  value = aws_rds_cluster.main.port
}

output "database_name" {
  value = aws_rds_cluster.main.database_name
}

output "cloudwatch_dashboard_url" {
  value = "https://console.aws.amazon.com/cloudwatch/home#dashboards:name=${aws_cloudwatch_dashboard.aurora.dashboard_name}"
}
