variable "name_prefix" {
  description = "Prefix applied to every resource name in this module."
  type        = string
}

variable "alert_email" {
  description = <<-EOT
    Email address subscribed to the SNS alert topic.

    Named `alert_email` specifically so the org-wide HCP variable set
    `shared-alert-email` supplies the value automatically -- no per-workspace
    variable to fill in.
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
  description = "Athena workgroup the analyzer runs in. Inherits that workgroup's bytes-scanned cutoff."
  type        = string
}

variable "results_bucket_arn" {
  description = "ARN of the bucket holding flow logs and Athena results."
  type        = string
}

variable "metric_namespace" {
  description = "CloudWatch namespace for the analyzer's custom metrics."
  type        = string
  default     = "FlowLogIntelligence"
}

variable "lookback_hours" {
  description = <<-EOT
    How many hours of flow logs each analyzer run examines.

    Must exceed the delivery lag or every run reads a partially-written window.
    Flow logs reach S3 in roughly 10 minutes, and files are published in 5-minute
    batches, so anything below 1 hour risks systematically undercounting the most
    recent data -- which would train the anomaly band on values that are low for
    reasons having nothing to do with the network.
  EOT
  type        = number
  default     = 2

  validation {
    condition     = var.lookback_hours >= 1 && var.lookback_hours <= 24
    error_message = "lookback_hours must be between 1 and 24."
  }
}

variable "schedule_expression" {
  description = "EventBridge schedule for the analyzer."
  type        = string
  default     = "rate(1 hour)"
}

variable "port_scan_alarm_threshold" {
  description = <<-EOT
    Number of scan-shaped sources in a window that triggers the alarm.

    A STATIC threshold, deliberately, where the volume alarms use anomaly
    detection. Anomaly detection learns what is normal and alerts on deviation --
    which is right for traffic volume, where normal genuinely is unknown and
    varies by time of day. It is the wrong tool here: it would learn a baseline
    rate of port scanning and then stop reporting it. Some quantities should not
    have a comfortable baseline.
  EOT
  type        = number
  default     = 1
}

variable "anomaly_detection_stddev" {
  description = <<-EOT
    Width of the anomaly detection band, in standard deviations.

    Lower is more sensitive and noisier. 2 is the usual starting point; raise it
    if the band proves too tight once real traffic has trained it.
  EOT
  type        = number
  default     = 2
}

variable "enable_anomaly_alarms" {
  description = <<-EOT
    Whether to create the anomaly-detection alarms.

    These cost $3.00/alarm/month against $0.10 for a static alarm, because each
    one bills three metrics: the value plus the upper and lower band. Charged
    hourly prorated, so a two-day build is cents -- but left running they are the
    most expensive thing in the monitoring layer.
  EOT
  type        = bool
  default     = true
}
