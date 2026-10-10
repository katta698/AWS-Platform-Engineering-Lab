output "invoke_url" { value = aws_apigatewayv2_stage.prod.invoke_url }
output "api_id" { value = aws_apigatewayv2_api.ebs.id }
output "execution_arn" { value = aws_apigatewayv2_api.ebs.execution_arn }
