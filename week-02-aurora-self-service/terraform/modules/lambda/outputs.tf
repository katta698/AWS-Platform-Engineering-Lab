output "webhook_receiver_arn" {
  value = aws_lambda_function.webhook_receiver.arn
}

output "webhook_receiver_name" {
  value = aws_lambda_function.webhook_receiver.function_name
}

output "db_provisioner_arn" {
  value = aws_lambda_function.db_provisioner.arn
}

output "db_provisioner_name" {
  value = aws_lambda_function.db_provisioner.function_name
}

output "status_updater_arn" {
  value = aws_lambda_function.status_updater.arn
}

output "status_updater_name" {
  value = aws_lambda_function.status_updater.function_name
}

output "lambda_role_arn" {
  value = aws_iam_role.lambda.arn
}
