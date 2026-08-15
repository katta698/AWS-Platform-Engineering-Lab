variable "aws_region" {
  description = "AWS region for the build."
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
    The variable is named `alert_email` specifically to pick that up -- do not
    rename it.
  EOT
  type        = string
  sensitive   = true
}

###############################################################################
# Network
###############################################################################

variable "vpc_cidr" {
  description = "CIDR block for the observed VPC."
  type        = string
  default     = "10.14.0.0/16"
}

variable "instance_type" {
  description = "Instance type for the lab instances."
  type        = string
  default     = "t4g.nano"
}

variable "enable_exposed_instance" {
  description = <<-EOT
    Create the internet-reachable instance that harvests real scanning traffic
    into REJECT records.

    Its security group has no ingress rules, so nothing can actually connect --
    the rejects are produced by those denials. Set false to build the analytics
    layer with no internet-reachable surface; the port-scan query still works,
    it just has far less to find.
  EOT
  type        = bool
  default     = true
}

variable "generator_team_tag" {
  description = "Value of the Team tag on the generator instance. This value is what appears in the instance_tag column and drives cost attribution."
  type        = string
  default     = "platform-engineering"
}

###############################################################################
# Flow log capture
###############################################################################

variable "flow_log_tag_keys" {
  description = <<-EOT
    Instance tag keys whose values get embedded in each flow record, in order.

    Record version 11 supports two instance tags. Every added field widens every
    record and every record is billed per GB, so this is not free -- pick the tag
    you actually need to group by.
  EOT
  type        = list(string)
  default     = ["Team"]

  validation {
    condition     = length(var.flow_log_tag_keys) <= 2
    error_message = "Flow log records support at most two instance tag fields."
  }
}

variable "max_aggregation_interval" {
  description = <<-EOT
    Maximum flow log aggregation interval in seconds: 60 or 600.

    600 keeps record volume (and therefore the $0.25/GB ingest charge) down.
    Note that ENIs on Nitro instances always aggregate at 1 minute or less
    regardless of this value.
  EOT
  type        = number
  default     = 600
}

variable "log_retention_days" {
  description = "Days before raw flow logs are expired from S3. Flow logs never stop arriving; this is what bounds the bill."
  type        = number
  default     = 30
}

###############################################################################
# Analytics
###############################################################################

variable "projection_start_year" {
  description = "Earliest year partition projection considers. Setting it before the first delivered log only widens the search space."
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

    Athena bills $5/TB scanned with no built-in limit, so this is the difference
    between a workgroup that is safe to share and one that is not.
  EOT
  type        = number
  default     = 10
}

###############################################################################
# Analysis and alarms
###############################################################################

variable "lookback_hours" {
  description = "Hours of flow logs each analyzer run examines. Must exceed the ~10 minute delivery lag."
  type        = number
  default     = 2
}

variable "port_scan_alarm_threshold" {
  description = "Scan-shaped sources in a window that trigger the alarm. Static by design -- see the monitoring module for why this one is not anomaly-detected."
  type        = number
  default     = 1
}

variable "anomaly_detection_stddev" {
  description = "Width of the anomaly detection band in standard deviations. Lower is more sensitive and noisier."
  type        = number
  default     = 2
}

variable "enable_anomaly_alarms" {
  description = <<-EOT
    Create the anomaly-detection alarms.

    $3.00/alarm/month each versus $0.10 for a static alarm, because each bills
    three metrics (value, upper band, lower band). Prorated hourly. Set false to
    keep only the static alarms.
  EOT
  type        = bool
  default     = true
}
