variable "name_prefix" {
  description = "Prefix applied to every resource name in this module."
  type        = string
}

variable "database_name" {
  description = "Name of the Glue catalog database."
  type        = string
}

variable "table_name" {
  description = "Name of the Glue catalog table for CloudTrail events."
  type        = string
}

variable "bucket_name" {
  description = "CloudTrail log bucket. Also holds Athena results under athena-results/."
  type        = string
}

variable "bucket_arn" {
  description = "ARN of the CloudTrail log bucket."
  type        = string
}

variable "organization_id" {
  description = <<-EOT
    AWS Organizations ID.

    An organization trail writes under AWSLogs/<org-id>/<account-id>/..., one path
    segment deeper than a single-account trail. This value is the difference
    between the table AWS documents and the table this build needs.
  EOT
  type        = string
}

variable "account_ids" {
  description = <<-EOT
    Account IDs to project as partitions -- the ACTIVE accounts only.

    This is the awkward part of the design and it should not be hidden. Partition
    projection needs a finite set for a non-date key, so accounts are projected as
    an `enum`. That means:

      * onboarding a new active account requires updating this list, or its events
        are invisible to every query while sitting perfectly happily in S3;
      * suspended or closed accounts are excluded, which costs nothing because
        they generate no API activity;
      * the projected partition space is accounts x regions x days, so keeping
        this list to accounts that actually do things keeps queries cheap.

    A Glue crawler would discover accounts automatically. It would also cost
    DPU-time on a schedule and lag behind new partitions. This is the honest
    trade-off of projection, and the strongest argument anyone could make against
    it here.
  EOT
  type        = list(string)

  validation {
    condition     = length(var.account_ids) > 0
    error_message = "At least one account ID must be projected, or the table can never return rows."
  }
}

variable "regions" {
  description = <<-EOT
    Regions to project as partitions.

    Must cover every region the trail could write to, not just the ones you use.
    A multi-region trail records activity everywhere, and one of this build's
    audit questions is "did anything happen in a region we do not use?" -- a
    question a narrow region list makes structurally unanswerable, because the
    table simply would not see those objects.

    Populated from the account's enabled regions rather than hardcoded.
  EOT
  type        = list(string)
}

variable "projection_start_year" {
  description = "Earliest year the projection considers. Setting it before the trail existed only widens the search space."
  type        = string
}

variable "projection_end_year" {
  description = "Latest year the projection considers."
  type        = string
}

variable "bytes_scanned_cutoff_gb" {
  description = <<-EOT
    Hard per-query scan ceiling in GB. Athena cancels anything exceeding it.

    Athena bills $5/TB scanned with no built-in limit, and CloudTrail JSON is
    verbose and uncompressed relative to columnar formats -- a forensic query
    written under incident pressure is exactly when someone forgets the date
    filter. This is the guardrail that makes the workgroup safe to share.
  EOT
  type        = number
  default     = 10

  validation {
    condition     = var.bytes_scanned_cutoff_gb >= 1
    error_message = "bytes_scanned_cutoff_gb must be at least 1."
  }
}

variable "named_queries" {
  description = "Map of query name => { description, sql } published into the workgroup."
  type = map(object({
    description = string
    sql         = string
  }))
  default = {}
}
