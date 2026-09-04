output "function_url" {
  description = "The MCP endpoint. Requires a SigV4-signed request; an unsigned call gets 403 from Lambda."
  value       = aws_lambda_function_url.server.function_url
}

output "function_name" {
  description = "Lambda function name, for logs and direct invoke."
  value       = aws_lambda_function.server.function_name
}

output "role_arn" {
  description = "The server's role. Read-only: it holds no write action on any service."
  value       = aws_iam_role.server.arn
}

output "cache_table_name" {
  description = "DynamoDB table caching Cost Explorer answers."
  value       = aws_dynamodb_table.cost_cache.name
}

output "alarm_name" {
  description = "CloudWatch alarm on server errors."
  value       = aws_cloudwatch_metric_alarm.errors.alarm_name
}
