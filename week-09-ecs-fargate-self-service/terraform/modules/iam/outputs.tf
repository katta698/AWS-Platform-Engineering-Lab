output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}

output "webhook_receiver_role_arn" {
  value = aws_iam_role.webhook_receiver.arn
}

output "fargate_provisioner_role_arn" {
  value = aws_iam_role.fargate_provisioner.arn
}

output "status_notifier_role_arn" {
  value = aws_iam_role.status_notifier.arn
}

output "step_functions_role_arn" {
  value = aws_iam_role.step_functions.arn
}
