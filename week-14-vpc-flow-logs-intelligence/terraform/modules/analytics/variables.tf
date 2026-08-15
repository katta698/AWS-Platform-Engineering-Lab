variable "name_prefix" {
  description = "Prefix applied to every resource name in this module."
  type        = string
}

variable "database_name" {
  description = "Name of the Glue catalog database."
  type        = string
}

variable "table_name" {
  description = "Name of the Glue catalog table for flow logs."
  type        = string
}

variable "bucket_name" {
  description = "Flow logs bucket name. Also holds Athena query results under athena-results/."
  type        = string
}

variable "bucket_arn" {
  description = "Flow logs bucket ARN."
  type        = string
}

variable "columns" {
  description = <<-EOT
    Ordered list of { name, type } for the flow log data columns.

    Order is load-bearing: it must match the order of fields in the flow log's
    custom log_format exactly. Parquet is read positionally against this schema, so
    a mismatch shifts every value one column sideways and produces a table that
    queries cleanly and answers wrongly. Both this and the log_format string are
    derived from a single list in the root module for that reason.
  EOT
  type = list(object({
    name = string
    type = string
  }))
}

variable "projection_start_year" {
  description = "Earliest year the partition projection will consider. Setting this earlier than the first delivered log only widens the search space for no benefit."
  type        = string
}

variable "projection_end_year" {
  description = "Latest year the partition projection will consider."
  type        = string
}

variable "bytes_scanned_cutoff_gb" {
  description = <<-EOT
    Hard per-query ceiling on bytes scanned, in GB. Athena cancels any query that
    exceeds it.

    Athena bills $5 per TB scanned with no upper bound, so a single careless
    `SELECT *` with no partition filter is an unbounded charge. This cutoff is what
    makes the workgroup safe to hand to someone who has not read the docs. AWS
    enforces a 10 MB minimum per query, so very small values are not meaningful.
  EOT
  type        = number
  default     = 10

  validation {
    condition     = var.bytes_scanned_cutoff_gb >= 1
    error_message = "bytes_scanned_cutoff_gb must be at least 1."
  }
}

variable "named_queries" {
  description = "Map of named query name => { description, sql } to publish into the workgroup."
  type = map(object({
    description = string
    sql         = string
  }))
  default = {}
}
