variable "name_prefix" {
  description = "Prefix applied to every resource name in this module."
  type        = string
}

variable "bucket_name" {
  description = "Name of the S3 bucket to create for CloudTrail logs."
  type        = string
}

variable "is_organization_trail" {
  description = <<-EOT
    Whether this is an AWS Organizations trail.

    An org trail captures events from every account in the organization into one
    bucket, which is the entire point of this build -- attribution across accounts
    is impossible when each account logs into its own silo.

    Two hard requirements, both verified before this was written:
      * this resource must live in the ORGANIZATION MANAGEMENT ACCOUNT, and
      * trusted access for cloudtrail.amazonaws.com must already be enabled in
        Organizations. There is no clean Terraform path for that enablement, so it
        is a documented prerequisite:
          aws organizations enable-aws-service-access \
            --service-principal cloudtrail.amazonaws.com
        Without it, CreateTrail fails with CloudTrailAccessNotEnabledException.
  EOT
  type        = bool
  default     = true
}

variable "is_multi_region_trail" {
  description = <<-EOT
    Capture events from every region, not just the home region.

    On by default because the audit question "did anything happen in a region we do
    not use?" cannot be answered by a single-region trail -- it has no visibility
    into the regions you are asking about. A single-region trail can only ever
    confirm activity where you were already looking.
  EOT
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = <<-EOT
    Days before CloudTrail objects are expired from S3.

    The console's own Event history keeps 90 days, which is the limitation this
    build exists to escape, so anything at or below 90 defeats the purpose. One
    year is the usual compliance floor.
  EOT
  type        = number
  default     = 365

  validation {
    condition     = var.log_retention_days > 90
    error_message = "Retention must exceed 90 days -- below that this build offers nothing over the CloudTrail console's built-in Event history."
  }
}

variable "enable_log_file_validation" {
  description = <<-EOT
    Have CloudTrail write signed digest files alongside the logs.

    Cheap, and it is what lets you later prove a log file was not altered after
    delivery. An audit trail nobody can vouch for is weaker evidence than one that
    carries its own integrity proof.
  EOT
  type        = bool
  default     = true
}

variable "home_region" {
  description = <<-EOT
    The trail's home region.

    Needed explicitly because the bucket policy scopes CloudTrail's access with an
    `aws:SourceArn` condition, and a trail ARN embeds its home region. Deriving it
    from a provider data source would silently produce the wrong ARN if the module
    were ever instantiated with an aliased provider.
  EOT
  type        = string
}
