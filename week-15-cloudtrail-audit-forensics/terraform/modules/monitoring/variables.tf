variable "name_prefix" {
  description = "Prefix applied to every resource name in this module."
  type        = string
}

variable "alert_email" {
  description = <<-EOT
    Email address subscribed to the SNS alert topic.

    Named `alert_email` so the org-wide HCP variable set `shared-alert-email`
    supplies the value automatically -- do not rename it.
  EOT
  type        = string
  sensitive   = true
}

variable "lambda_source_dir" {
  description = "Path to the analyzer Lambda source directory."
  type        = string
}

variable "lambda_build_dir" {
  description = "Path where the Lambda zip is written. Gitignored."
  type        = string
}

variable "athena_database" {
  description = "Glue database the analyzer queries."
  type        = string
}

variable "athena_table" {
  description = "Glue table the analyzer queries."
  type        = string
}

variable "athena_workgroup" {
  description = "Athena workgroup the analyzer runs in. Inherits that workgroup's scan ceiling."
  type        = string
}

variable "results_bucket_arn" {
  description = "ARN of the bucket holding CloudTrail logs and Athena results."
  type        = string
}

variable "metric_namespace" {
  description = "CloudWatch namespace for the analyzer's custom metrics."
  type        = string
  default     = "CloudTrailAudit"
}

variable "expected_regions" {
  description = <<-EOT
    Regions this estate legitimately uses.

    Anything mutating outside this list is counted as unexpected-region activity.
    Keep it honest: adding a region here to silence an alarm is the same as
    turning the alarm off.
  EOT
  type        = list(string)
  default     = ["us-east-1"]
}

variable "schedule_expression" {
  description = <<-EOT
    EventBridge schedule for the analyzer.

    Daily rather than hourly. The three scheduled questions -- root usage,
    console sign-in without MFA, activity in unused regions -- do not need
    sub-day latency to be actionable, and CloudTrail delivers on a 5-15 minute
    lag with occasional longer tails, so a tighter schedule mostly re-reads the
    same partition and pays Athena for the privilege.
  EOT
  type        = string
  default     = "rate(1 day)"
}

variable "lambda_timeout_seconds" {
  description = "Lambda timeout. Bound by Athena query latency, not compute."
  type        = number
  default     = 600
}
