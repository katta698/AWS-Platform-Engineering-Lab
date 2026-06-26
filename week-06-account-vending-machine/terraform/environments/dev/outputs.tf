output "api_gateway_url" {
  description = "ServiceNow webhook endpoint"
  value       = module.api_gateway.api_url
}

output "state_machine_arn" {
  value = module.step_functions.state_machine_arn
}

output "ou_ids" {
  description = "Map of OU name to OU ID"
  value       = module.organizations.ou_ids
}

output "sandbox_scp_id" {
  value = module.scp.scp_id
}
