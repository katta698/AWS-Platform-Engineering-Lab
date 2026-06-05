output "webhook_receiver_arn"    { value = aws_lambda_function.this["webhook_receiver"].arn }
output "fleet_onboarder_arn"     { value = aws_lambda_function.this["fleet_onboarder"].arn }
output "patch_orchestrator_arn"  { value = aws_lambda_function.this["patch_orchestrator"].arn }
output "status_updater_arn"      { value = aws_lambda_function.this["status_updater"].arn }
