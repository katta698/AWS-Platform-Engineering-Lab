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
    Value of the `Region` dimension on AWS/WAFV2 metrics.

    For a REGIONAL web ACL this is the region name (e.g. us-east-1). For a
    CLOUDFRONT web ACL, metrics are published in us-east-1 with this dimension
    set to the literal string "Global". Getting this wrong produces an alarm
    stuck in INSUFFICIENT_DATA forever rather than an error -- verify against
    `aws cloudwatch list-metrics --namespace AWS/WAFV2` after the first apply.
  EOT
  type        = string
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
