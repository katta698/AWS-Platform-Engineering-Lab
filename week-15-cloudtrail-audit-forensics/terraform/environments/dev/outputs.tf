###############################################################################
# Capture
###############################################################################

output "trail_name" {
  description = "Name of the organization trail."
  value       = module.audit_trail.trail_name
}

output "trail_arn" {
  description = "ARN of the organization trail."
  value       = module.audit_trail.trail_arn
}

output "log_bucket" {
  description = "Bucket receiving CloudTrail events."
  value       = module.audit_trail.bucket_name
}

output "organization_id" {
  description = "Organization ID. First path segment an org trail writes under, and the root of the Athena table location."
  value       = module.audit_trail.organization_id
}

###############################################################################
# Query layer
###############################################################################

output "athena_database" {
  description = "Glue database holding the CloudTrail table."
  value       = module.analytics.database_name
}

output "athena_table" {
  description = "Fully qualified table for queries."
  value       = module.analytics.qualified_table
}

output "athena_workgroup" {
  description = "Athena workgroup. Queries must run here to inherit the scan ceiling."
  value       = module.analytics.workgroup_name
}

output "projected_accounts" {
  description = <<-EOT
    Account IDs projected as partitions -- the ACTIVE accounts, derived from live
    organization state.

    Worth reading back after apply. An account missing from this list has its
    events sitting in S3 and invisible to every query, with no error anywhere.
  EOT
  value       = local.active_account_ids
}

output "projected_region_count" {
  description = "Number of regions projected. Covers all enabled regions, not just the ones in use, so unexpected-region activity is actually visible."
  value       = length(data.aws_regions.enabled.names)
}

output "projected_partition_space" {
  description = "Rough projected partition count (accounts x regions x days/year). Projection computes these at query time, so a query with no date filter asks Athena to consider all of them."
  value       = module.analytics.projected_partition_count
}

output "partition_location_template" {
  description = <<-EOT
    The resolved partition projection template.

    Compare against a real delivered key before trusting any query result:

      aws s3 ls s3://<bucket>/AWSLogs/ --recursive | tail -3

    A mismatch returns zero rows and reports SUCCEEDED -- there is no error to
    see, so this string comparison is the check.
  EOT
  value       = module.analytics.storage_location_template
}

output "saved_queries" {
  description = "Saved Athena queries available in the console. Run partition-sanity-check first."
  value       = keys(module.analytics.named_query_ids)
}

###############################################################################
# Analysis and alerting
###############################################################################

output "analyzer_function_name" {
  description = "Audit analyzer. Force a run instead of waiting a day: aws lambda invoke --function-name <name> out.json"
  value       = module.monitoring.analyzer_function_name
}

output "analyzer_log_group" {
  description = "Analyzer log group."
  value       = module.monitoring.analyzer_log_group
}

output "metric_namespace" {
  description = "CloudWatch namespace for the analyzer's metrics."
  value       = module.monitoring.metric_namespace
}

output "alarm_names" {
  description = "Every alarm created. All static thresholds -- no anomaly detectors, so teardown leaves no orphans."
  value       = module.monitoring.alarm_names
}

output "sns_topic_arn" {
  description = "Alert topic. The email subscription must be confirmed before any alarm can notify."
  value       = module.monitoring.sns_topic_arn
}

###############################################################################
# Operational notes
###############################################################################

output "cost_note" {
  description = "The thing to remember about this build's running cost."
  value = join(" ", [
    "Management events are the FREE first copy, so trail ingestion costs nothing.",
    "The running cost is S3 storage (~$0.023/GB-month, expiring at ${var.log_retention_days} days)",
    "plus Athena at $5/TB scanned, capped at ${var.bytes_scanned_cutoff_gb} GB per query.",
    "No NAT gateway, no always-on compute, no anomaly-detection alarms.",
    "This is a materially cheaper week than 13 or 14.",
  ])
}

output "prerequisite_note" {
  description = "Manual step required before the first apply, and easy to forget on a rebuild."
  value = join(" ", [
    "Organization trails require trusted access:",
    "aws organizations enable-aws-service-access --service-principal cloudtrail.amazonaws.com",
    "Without it CreateTrail fails with CloudTrailAccessNotEnabledException.",
    "There is no clean Terraform path, so this is a documented manual prerequisite.",
  ])
}
