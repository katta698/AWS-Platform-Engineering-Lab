output "function_arn" { value = aws_lambda_function.ebs_savings.arn }
output "function_name" { value = aws_lambda_function.ebs_savings.function_name }
output "role_arn" { value = aws_iam_role.lambda.arn }
