###############################################################################
# Network
###############################################################################

output "vpc_id" {
  description = "ID of the observed VPC."
  value       = module.network_lab.vpc_id
}

output "nat_gateway_public_ip" {
  description = "Public IP of the NAT gateway. Every NAT-path egress flow appears to come from here -- which is why pkt_srcaddr matters."
  value       = module.network_lab.nat_public_ip
}

output "exposed_instance_public_ip" {
  description = "Public IP of the exposed instance. Unsolicited traffic to it becomes REJECT records within minutes."
  value       = module.network_lab.exposed_public_ip
}

output "generator_instance_id" {
  description = "Traffic generator instance ID. Connect with: aws ssm start-session --target <id>"
  value       = module.network_lab.generator_instance_id
}

###############################################################################
# Capture
###############################################################################

output "flow_logs_bucket" {
  description = "Bucket receiving flow logs."
  value       = module.flow_logs.bucket_name
}

output "flow_log_id" {
  description = "Flow log subscription ID. Appears in every delivered object name."
  value       = module.flow_logs.flow_log_id
}

output "flow_log_format" {
  description = <<-EOT
    The custom log format actually applied.

    Worth reading back after apply: the field ORDER here must match the Glue
    table's column order, and both are generated from one list precisely so they
    cannot disagree.
  EOT
  value       = local.log_format
}

output "flow_log_field_count" {
  description = "Number of fields captured per record. More fields means wider records and more GB billed at $0.25/GB."
  value       = length(local.flow_log_fields)
}

###############################################################################
# Query layer
###############################################################################

output "athena_database" {
  description = "Glue database holding the flow log table."
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

output "partition_location_template" {
  description = <<-EOT
    The partition projection template.

    Compare this against a real delivered key before trusting any query result:

      aws s3 ls s3://<bucket>/AWSLogs/ --recursive | tail -3

    A mismatch returns zero rows and reports success -- there is no error to see.
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
  description = "Analyzer Lambda. Force a run instead of waiting an hour: aws lambda invoke --function-name <name> out.json"
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
  description = "Every alarm created by this build."
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
    "NAT gateway is ~75% of this build's cost at $0.045/hr plus $0.045/GB processed,",
    "and it bills whether or not any traffic flows.",
    "Two anomaly-detection alarms add $3.00/month each, prorated hourly.",
    "Roughly $3 for a 48-hour build-test-destroy; roughly $33/month if left running.",
  ])
}
