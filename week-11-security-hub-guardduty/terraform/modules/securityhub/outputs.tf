output "standards_arn" {
  description = "ARN of the subscribed FSBP standard."
  value       = aws_securityhub_standards_subscription.fsbp.standards_arn
}

output "automation_rule_arn" {
  description = "ARN of the production-escalation automation rule."
  value       = aws_securityhub_automation_rule.escalate_prod.arn
}

output "account_id" {
  description = "Security Hub account resource id (region-scoped enablement)."
  value       = aws_securityhub_account.this.id
}
