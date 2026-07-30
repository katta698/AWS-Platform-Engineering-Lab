output "conformance_pack_name" {
  description = "Name of the deployed conformance pack."
  value       = aws_config_conformance_pack.this.name
}

output "conformance_pack_arn" {
  description = "ARN of the deployed conformance pack."
  value       = aws_config_conformance_pack.this.arn
}

output "ssm_automation_role_arn" {
  description = "IAM role SSM Automation assumes to perform remediations."
  value       = aws_iam_role.ssm_automation.arn
}

output "config_rule_names" {
  description = "Names of the 3 Config rules defined inside the conformance pack template (not standalone resources -- see main.tf)."
  value = {
    required_tags = "week12-required-tags"
    s3_versioning = "week12-s3-bucket-versioning-enabled"
    s3_encryption = "week12-s3-bucket-sse-enabled"
  }
}
