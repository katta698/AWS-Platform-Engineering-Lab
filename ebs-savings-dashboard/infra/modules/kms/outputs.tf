output "cur_key_arn" { value = aws_kms_key.cur.arn }
output "athena_key_arn" { value = aws_kms_key.athena.arn }
output "lambda_key_arn" { value = aws_kms_key.lambda.arn }
output "frontend_logs_key_arn" { value = aws_kms_key.frontend_logs.arn }
