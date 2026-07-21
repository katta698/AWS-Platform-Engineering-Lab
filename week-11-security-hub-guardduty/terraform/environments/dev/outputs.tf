output "securityhub_standards_arn" {
  description = "Subscribed FSBP standard ARN."
  value       = module.securityhub.standards_arn
}

output "securityhub_automation_rule_arn" {
  description = "Production-escalation automation rule ARN."
  value       = module.securityhub.automation_rule_arn
}

output "guardduty_detector_id" {
  description = "GuardDuty detector id."
  value       = module.guardduty.detector_id
}

output "alerts_sns_topic_arn" {
  description = "SNS topic carrying remediation results and threat alerts."
  value       = module.remediation.sns_topic_arn
}

output "remediation_dlq_url" {
  description = "Dead-letter queue URL for failed remediations."
  value       = module.remediation.dlq_url
}

output "remediation_lambda_names" {
  description = "Deployed remediation Lambda function names."
  value       = module.remediation.lambda_function_names
}

output "remediation_event_rules" {
  description = "EventBridge rule names routing findings to each Lambda."
  value       = module.remediation.event_rule_names
}
