output "api_gateway_url" {
  description = "POST this URL from ServiceNow to trigger database provisioning"
  value       = module.api_gateway.api_gateway_url
}

output "aurora_writer_endpoint" {
  description = "Aurora writer endpoint — use for all writes"
  value       = module.aurora.cluster_endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora reader endpoint — use for read-only queries"
  value       = module.aurora.cluster_reader_endpoint
}

output "master_secret_name" {
  description = "Retrieve Aurora admin credentials with: aws secretsmanager get-secret-value --secret-id <this>"
  value       = module.secrets.master_secret_name
}

output "state_machine_arn" {
  value = module.step_functions.state_machine_arn
}

output "cloudwatch_dashboard_url" {
  value = module.aurora.cloudwatch_dashboard_url
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
