output "api_endpoint" {
  description = "Base URL. POST /checkout, /reports or /exports."
  value       = aws_apigatewayv2_api.this.api_endpoint
}

output "function_names" {
  description = "Service name -> Lambda function name."
  value       = { for k, v in aws_lambda_function.fn : k => v.function_name }
}

output "table_name" {
  value = aws_dynamodb_table.shared.name
}
