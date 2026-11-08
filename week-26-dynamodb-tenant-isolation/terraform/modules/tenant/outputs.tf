output "function_name" {
  value = aws_lambda_function.this.function_name
}

output "role_arn" {
  value = aws_iam_role.this.arn
}

output "policy_json" {
  description = "The data-access policy as IAM sees it. The lab prints this next to the result it produced."
  value       = local.policy
}
