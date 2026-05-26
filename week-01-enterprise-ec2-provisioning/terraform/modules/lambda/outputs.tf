output "servicenow_receiver_arn" {
  value = aws_lambda_function.servicenow_receiver.arn
}

output "servicenow_receiver_invoke_arn" {
  value = aws_lambda_function.servicenow_receiver.invoke_arn
}

output "deployment_trigger_arn" {
  value = aws_lambda_function.deployment_trigger.arn
}

output "status_updater_arn" {
  value = aws_lambda_function.status_updater.arn
}
