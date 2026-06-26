output "ou_ids" {
  description = "Map of OU name to OU ID"
  value       = { for name, ou in aws_organizations_organizational_unit.ou : name => ou.id }
}

output "ou_arns" {
  description = "Map of OU name to OU ARN"
  value       = { for name, ou in aws_organizations_organizational_unit.ou : name => ou.arn }
}
