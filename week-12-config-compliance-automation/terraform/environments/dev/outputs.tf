output "conformance_pack_name" {
  description = "Name of the deployed conformance pack (compliance dashboard unit)."
  value       = module.config_compliance.conformance_pack_name
}

output "config_rule_names" {
  description = "Names of the 3 Config rules this week adds, defined inside the conformance pack."
  value       = module.config_compliance.config_rule_names
}

output "ssm_automation_role_arn" {
  description = "IAM role SSM Automation assumes to perform remediations."
  value       = module.config_compliance.ssm_automation_role_arn
}

output "digest_sns_topic_arn" {
  description = "SNS topic carrying the daily compliance digest."
  value       = module.reporter.sns_topic_arn
}

output "reporter_lambda_name" {
  description = "Deployed compliance_reporter Lambda function name."
  value       = module.reporter.lambda_function_name
}

output "reporter_dlq_url" {
  description = "Dead-letter queue URL for failed reporter invocations."
  value       = module.reporter.dlq_url
}
