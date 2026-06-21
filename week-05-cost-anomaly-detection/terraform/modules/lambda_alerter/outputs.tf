output "lambda_arn" {
  description = "ARN of the cost alerter Lambda function"
  value       = aws_lambda_function.cost_alerter.arn
}

output "lambda_name" {
  description = "Name of the cost alerter Lambda function"
  value       = aws_lambda_function.cost_alerter.function_name
}
