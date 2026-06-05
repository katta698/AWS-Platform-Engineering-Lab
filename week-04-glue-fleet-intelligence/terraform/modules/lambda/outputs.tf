output "webhook_receiver_arn"  { value = aws_lambda_function.webhook_receiver.arn }
output "webhook_receiver_name" { value = aws_lambda_function.webhook_receiver.function_name }
output "glue_trigger_arn"      { value = aws_lambda_function.glue_trigger.arn }
output "glue_trigger_name"     { value = aws_lambda_function.glue_trigger.function_name }
output "status_updater_arn"    { value = aws_lambda_function.status_updater.arn }
output "status_updater_name"   { value = aws_lambda_function.status_updater.function_name }
