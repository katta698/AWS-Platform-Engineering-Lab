output "api_url" {
  description = "ServiceNow webhook endpoint URL"
  value       = "${aws_api_gateway_stage.webhook.invoke_url}/webhook"
}

output "api_id" {
  value = aws_api_gateway_rest_api.webhook.id
}
