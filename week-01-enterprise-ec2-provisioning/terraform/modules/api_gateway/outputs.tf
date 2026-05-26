output "api_endpoint" {
  value       = "${aws_api_gateway_stage.main.invoke_url}/provision"
  description = "Full URL for the /provision POST endpoint — use this in ServiceNow"
}

output "execution_arn" {
  value       = aws_api_gateway_rest_api.main.execution_arn
  description = "Execution ARN for Lambda permission"
}

output "api_id" {
  value = aws_api_gateway_rest_api.main.id
}
