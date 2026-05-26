output "master_secret_arn" {
  value = aws_secretsmanager_secret.master.arn
}

output "master_secret_name" {
  value = aws_secretsmanager_secret.master.name
}

output "rotation_lambda_arn" {
  value = aws_lambda_function.rotation.arn
}

output "rotation_lambda_name" {
  value = aws_lambda_function.rotation.function_name
}
