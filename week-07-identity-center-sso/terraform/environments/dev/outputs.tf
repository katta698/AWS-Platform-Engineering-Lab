output "target_account_ids" {
  description = "Accounts the SSO assignments were provisioned into"
  value       = local.target_account_ids
}

output "permission_set_arns" {
  value = module.identity_center.permission_set_arns
}

output "group_ids" {
  value = module.identity_center.group_ids
}

output "assignment_count" {
  value = module.identity_center.assignment_count
}
