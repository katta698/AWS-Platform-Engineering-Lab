output "scp_id" {
  description = "ID of the Sandbox guardrail SCP"
  value       = aws_organizations_policy.sandbox_guardrail.id
}

output "scp_arn" {
  description = "ARN of the Sandbox guardrail SCP"
  value       = aws_organizations_policy.sandbox_guardrail.arn
}
