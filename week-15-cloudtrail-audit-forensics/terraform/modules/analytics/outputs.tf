output "database_name" {
  description = "Glue catalog database name."
  value       = aws_glue_catalog_database.this.name
}

output "table_name" {
  description = "Glue catalog table name for CloudTrail events."
  value       = aws_glue_catalog_table.cloudtrail.name
}

output "qualified_table" {
  description = "Fully qualified table reference for use in queries."
  value       = "\"${aws_glue_catalog_database.this.name}\".\"${aws_glue_catalog_table.cloudtrail.name}\""
}

output "workgroup_name" {
  description = "Athena workgroup. Queries must run here to inherit the scan ceiling."
  value       = aws_athena_workgroup.this.name
}

output "results_location" {
  description = "S3 location Athena writes query results to."
  value       = "s3://${var.bucket_name}/athena-results/"
}

output "storage_location_template" {
  description = <<-EOT
    The resolved partition projection template.

    Surfaced deliberately so it can be compared against a real delivered S3 key
    after the first events land. A projection mismatch returns zero rows and
    reports SUCCEEDED, so this string comparison is the check -- re-reading the
    Terraform cannot detect it.
  EOT
  value       = local.storage_location_template
}

output "projected_partition_count" {
  description = <<-EOT
    Rough size of the projected partition space: accounts x regions x days/year.

    Worth watching. Projection computes partitions at query time, so a query
    without a date filter asks Athena to consider all of them. This is the number
    that makes the case for keeping the account and region enums tight.
  EOT
  value       = length(var.account_ids) * length(var.regions) * 365
}

output "named_query_ids" {
  description = "Map of saved query name => Athena named query ID."
  value       = { for k, v in aws_athena_named_query.this : k => v.id }
}
