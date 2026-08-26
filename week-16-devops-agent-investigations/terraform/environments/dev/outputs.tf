output "agent_space_id" {
  description = "Agent space ID. Needed by every devops-agent CLI call and by the console URL."
  value       = module.agent_space.agent_space_id
}

output "agent_space_arn" {
  description = "Agent space ARN, for IAM policies scoped to this space."
  value       = module.agent_space.arn
}

output "console_url" {
  description = "Where a human actually drives the agent. The CLI can create a chat execution but cannot send it a message -- interaction happens in the Operator App."
  value       = "https://${var.aws_region}.console.aws.amazon.com/devops-agent/home?region=${var.aws_region}#/agent-spaces/${module.agent_space.agent_space_id}"
}

output "usage_meter_command" {
  description = "This week has no service-enforced spend ceiling. Run this before and after anything the agent does."
  value       = "./scripts/measure_usage.sh"
}
