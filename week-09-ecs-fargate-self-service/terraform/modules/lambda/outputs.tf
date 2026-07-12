output "webhook_receiver_arn" {
  value = aws_lambda_function.webhook_receiver.arn
}

output "webhook_receiver_name" {
  value = aws_lambda_function.webhook_receiver.function_name
}

output "fargate_provisioner_arn" {
  value = aws_lambda_function.fargate_provisioner.arn
}

output "status_notifier_arn" {
  value = aws_lambda_function.status_notifier.arn
}
