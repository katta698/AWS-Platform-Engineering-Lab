output "api_gateway_url" {
  value = "${aws_api_gateway_stage.main.invoke_url}/provision"
}

output "api_id" {
  value = aws_api_gateway_rest_api.main.id
}
