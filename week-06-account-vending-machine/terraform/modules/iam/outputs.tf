output "webhook_receiver_role_arn" {
  value = aws_iam_role.webhook_receiver.arn
}

output "account_creator_role_arn" {
  value = aws_iam_role.account_creator.arn
}

output "account_mover_role_arn" {
  value = aws_iam_role.account_mover.arn
}

output "status_notifier_role_arn" {
  value = aws_iam_role.status_notifier.arn
}

output "step_functions_role_arn" {
  value = aws_iam_role.step_functions.arn
}
