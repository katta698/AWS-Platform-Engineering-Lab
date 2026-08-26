output "agent_space_id" {
  description = "The agent space ID. Every association, trigger and CLI call needs this."
  value       = awscc_devopsagent_agent_space.this.agent_space_id
}

output "arn" {
  description = "ARN of the agent space, for IAM policies scoped to this space rather than to devops-agent generally."
  value       = awscc_devopsagent_agent_space.this.arn
}

output "name" {
  description = "Name of the agent space, echoed for use in console URLs and scripts."
  value       = awscc_devopsagent_agent_space.this.name
}
