output "database_name" {
  description = "Glue catalog database name."
  value       = aws_glue_catalog_database.this.name
}

output "table_name" {
  description = "Glue catalog table name for flow logs."
  value       = aws_glue_catalog_table.flow_logs.name
}

output "qualified_table" {
  description = "Fully qualified table reference for use in queries."
  value       = "${aws_glue_catalog_database.this.name}.${aws_glue_catalog_table.flow_logs.name}"
}

output "workgroup_name" {
  description = "Athena workgroup name. Queries must run in this workgroup to inherit the scan cutoff."
  value       = aws_athena_workgroup.this.name
}

output "results_location" {
  description = "S3 location Athena writes query results to."
  value       = "s3://${var.bucket_name}/athena-results/"
}

output "storage_location_template" {
  description = <<-EOT
    The resolved partition projection template.

    Surfaced as an output specifically so it can be eyeballed against a real
    delivered S3 key after the first logs land -- projection mismatches return
    zero rows rather than raising an error, so this comparison is the check.
  EOT
  value       = local.storage_location_template
}

output "named_query_ids" {
  description = "Map of saved query name => Athena named query ID."
  value       = { for k, v in aws_athena_named_query.this : k => v.id }
}
