output "webhook_receiver_arn" {
  value = aws_lambda_function.webhook_receiver.arn
}

output "webhook_receiver_name" {
  value = aws_lambda_function.webhook_receiver.function_name
}

output "account_creator_arn" {
  value = aws_lambda_function.account_creator.arn
}

output "account_mover_arn" {
  value = aws_lambda_function.account_mover.arn
}

output "status_notifier_arn" {
  value = aws_lambda_function.status_notifier.arn
}
