output "ec2_instance_profile_name"   { value = aws_iam_instance_profile.ec2.name }
output "ec2_role_arn"                { value = aws_iam_role.ec2.arn }
output "ssm_automation_role_arn"     { value = aws_iam_role.ssm_automation.arn }
output "maintenance_window_role_arn" { value = aws_iam_role.maintenance_window.arn }
output "lambda_role_arn"             { value = aws_iam_role.lambda.arn }
output "step_functions_role_arn"     { value = aws_iam_role.step_functions.arn }
