variable "aws_region" {
  description = "AWS region for the build. Also the trail's home region."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name, used in tags."
  type        = string
  default     = "dev"
}

variable "alert_email" {
  description = <<-EOT
    Email address for alarm notifications.

    Supplied automatically by the org-wide HCP variable set `shared-alert-email`.
    Named `alert_email` specifically to pick that up -- do not rename it.
  EOT
  type        = string
  sensitive   = true
}

###############################################################################
# Trail
###############################################################################

variable "is_organization_trail" {
  description = <<-EOT
    Capture events from every account in the organization, not just this one.

    Requires that this runs in the MANAGEMENT ACCOUNT and that trusted access is
    already enabled:

      aws organizations enable-aws-service-access \
        --service-principal cloudtrail.amazonaws.com

    Without it, CreateTrail fails with CloudTrailAccessNotEnabledException. There
    is no clean Terraform path for that enablement, so it is a documented manual
    prerequisite -- the same shape as Week 6's SCP policy-type enablement.

    Set false to build the whole pipeline against a single account.
  EOT
  type        = bool
  default     = true
}

variable "is_multi_region_trail" {
  description = <<-EOT
    Record events in every region.

    Leave this on. The audit question "did anything happen in a region we do not
    use?" is structurally unanswerable with a single-region trail -- it has no
    visibility into the regions being asked about, so it returns a confident
    empty result.
  EOT
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = <<-EOT
    Days before CloudTrail objects expire from S3.

    Must exceed 90. The CloudTrail console's own Event history already keeps 90
    days, so anything at or below that gives this build no reason to exist.
  EOT
  type        = number
  default     = 365
}

variable "enable_log_file_validation" {
  description = "Write signed digest files so a log can later be proven unaltered."
  type        = bool
  default     = true
}

###############################################################################
# Analytics
###############################################################################

variable "projection_start_year" {
  description = "Earliest year partition projection considers. Before the trail existed only widens the search space."
  type        = string
  default     = "2026"
}

variable "projection_end_year" {
  description = "Latest year partition projection considers."
  type        = string
  default     = "2027"
}

variable "bytes_scanned_cutoff_gb" {
  description = <<-EOT
    Per-query scan ceiling in GB. Athena cancels anything exceeding it.

    Athena bills $5/TB scanned with no built-in limit, and CloudTrail JSON is
    verbose and uncompressed compared with columnar formats. A forensic query
    written under incident pressure is exactly when the date filter gets
    forgotten.
  EOT
  type        = number
  default     = 10
}

###############################################################################
# Analysis and alarms
###############################################################################

variable "expected_regions" {
  description = <<-EOT
    Regions this estate legitimately uses.

    Mutating activity anywhere else is counted as unexpected-region activity and
    alarms. Adding a region here to silence an alarm is the same as switching the
    alarm off -- do it only when the region is genuinely in use.
  EOT
  type        = list(string)
  default     = ["us-east-1"]
}

variable "schedule_expression" {
  description = "EventBridge schedule for the audit analyzer. Daily is deliberate -- see the monitoring module."
  type        = string
  default     = "rate(1 day)"
}

variable "lambda_timeout_seconds" {
  description = "Analyzer timeout. Bound by Athena query latency, not compute."
  type        = number
  default     = 600
}
