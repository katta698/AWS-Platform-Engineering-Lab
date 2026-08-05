variable "name_prefix" {
  description = "Prefix for every resource this module creates."
  type        = string
}

variable "web_acl_name" {
  description = "Name of the web ACL to alarm on. Becomes the WebACL metric dimension."
  type        = string
}

variable "metric_region_dimension" {
  description = <<-EOT
    Value of the `Region` dimension on AWS/WAFV2 metrics, or null to omit the
    dimension entirely.

    For a REGIONAL web ACL this is the region name (e.g. us-east-1).

    For a CLOUDFRONT web ACL it must be **null**. CloudFront-scope metrics carry
    NO Region dimension at all -- they are published in us-east-1 with only
    WebACL and Rule. Passing the literal "Global" (a plausible-looking guess,
    and what this module originally did) matches no metric series, so the alarm
    sits in INSUFFICIENT_DATA forever instead of erroring. Confirmed live on
    2026-08-05 via `aws cloudwatch list-metrics --namespace AWS/WAFV2`.
  EOT
  type        = string
  default     = null
}

variable "alert_email" {
  description = "Address that receives WAF alarms. Supplied by the global HCP variable set `shared-alert-email`."
  type        = string
  sensitive   = true
}

variable "blocked_requests_threshold" {
  description = "BlockedRequests in a 5-minute period before the alarm fires."
  type        = number
  default     = 50
}

variable "counted_requests_threshold" {
  description = <<-EOT
    CountedRequests in a 5-minute period before the count-mode alarm fires.
    This alarm is what makes Count mode useful: it tells you a rule matched
    something without that rule having blocked anything.
  EOT
  type        = number
  default     = 50
}

variable "tags" {
  description = "Tags applied to taggable resources in this module."
  type        = map(string)
  default     = {}
}
