output "api_gateway_url" {
  value       = module.api_gateway.api_gateway_url
  description = "POST endpoint — use this in ServiceNow Outbound REST Message"
}

output "session_logs_bucket" {
  value       = module.ssm.session_logs_bucket
  description = "S3 bucket storing all Session Manager logs and patch reports"
}

output "maintenance_window_id" {
  value       = module.ssm.maintenance_window_id
  description = "SSM Maintenance Window ID — weekly Sunday 02:00 UTC"
}

output "onboard_document_name" {
  value       = module.ssm.onboard_document_name
  description = "SSM Automation document for instance onboarding"
}

output "patch_fleet_document_name" {
  value       = module.ssm.patch_fleet_document_name
  description = "SSM Automation document for fleet patching"
}

output "state_machine_arn" {
  value       = module.step_functions.state_machine_arn
  description = "Step Functions state machine ARN"
}

output "asg_name" {
  value       = module.ec2_fleet.asg_name
  description = "Auto Scaling Group name — instances appear in SSM Fleet Manager"
}

output "cloudwatch_dashboard_url" {
  value       = module.cloudwatch.cloudwatch_dashboard_url
  description = "CloudWatch dashboard URL"
}
