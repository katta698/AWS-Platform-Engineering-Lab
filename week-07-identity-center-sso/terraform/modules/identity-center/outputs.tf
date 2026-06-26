output "permission_set_arns" {
  description = "Permission set ARN, keyed by group name"
  value       = { for k, v in aws_ssoadmin_permission_set.this : k => v.arn }
}

output "group_ids" {
  description = "Identity Store group ID, keyed by group name"
  value       = { for k, v in aws_identitystore_group.this : k => v.group_id }
}

output "user_ids" {
  description = "Identity Store user ID, keyed by username"
  value       = { for k, v in aws_identitystore_user.this : k => v.user_id }
}

output "assignment_count" {
  description = "Number of group x account assignments provisioned"
  value       = length(aws_ssoadmin_account_assignment.this)
}
