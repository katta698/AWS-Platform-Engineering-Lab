output "api_gateway_url"          { value = "${aws_api_gateway_stage.this.invoke_url}/fleet" }
output "api_gateway_execution_arn" { value = aws_api_gateway_rest_api.this.execution_arn }
