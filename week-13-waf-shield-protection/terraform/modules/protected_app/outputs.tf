output "api_stage_arn" {
  description = "ARN of the API Gateway stage. This is what a REGIONAL web ACL associates with -- note the stage, not the REST API itself, is the associable resource."
  value       = "arn:aws:apigateway:${data.aws_region.current.region}::/restapis/${aws_api_gateway_rest_api.this.id}/stages/${aws_api_gateway_stage.this.stage_name}"
}

output "api_invoke_url" {
  description = "Direct-to-origin URL, bypassing CloudFront. Used by the attack simulation to prove the regional WAF still inspects requests that skip the edge."
  value       = aws_api_gateway_stage.this.invoke_url
}

output "cloudfront_url" {
  description = "Public edge URL. The path a normal user takes."
  value       = "https://${aws_cloudfront_distribution.this.domain_name}"
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID."
  value       = aws_cloudfront_distribution.this.id
}

output "lambda_function_name" {
  description = "Name of the echo function."
  value       = aws_lambda_function.echo.function_name
}

output "lambda_log_group_name" {
  description = "Log group for the echo function -- shows which requests actually reached the origin."
  value       = aws_cloudwatch_log_group.lambda.name
}
