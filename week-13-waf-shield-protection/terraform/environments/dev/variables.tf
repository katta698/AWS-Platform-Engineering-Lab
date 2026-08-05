variable "aws_region" {
  description = "Region for the regional web ACL, API Gateway, and Lambda. The edge web ACL is always created in us-east-1 regardless of this value."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name, used in tags."
  type        = string
  default     = "dev"
}

variable "stage_name" {
  description = "API Gateway stage name."
  type        = string
  default     = "prod"
}

variable "count_mode" {
  description = <<-EOT
    Deploy every rule in Count mode (true) or enforcing (false).

    Start at true. In Count mode WAF records what each rule would have done
    without blocking anything, which is the only safe way to find out whether
    a managed rule group rejects legitimate traffic in your application.
    Flip to false only after reviewing the counted matches.
  EOT
  type        = bool
  default     = true
}

variable "rate_limit" {
  description = "Requests from one IP within the evaluation window before the rate-based rule triggers. Low here because the demo generates its floods from a single machine."
  type        = number
  default     = 100
}

variable "rate_evaluation_window_sec" {
  description = "Rate-based rule lookback window in seconds. Valid: 60, 120, 300, 600."
  type        = number
  default     = 60
}

variable "blocked_ip_cidrs" {
  description = "Break-glass IP deny list in CIDR notation. Empty by default."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Retention for WAF and Lambda log groups. WAF logs one record per inspected request, so keep this short."
  type        = number
  default     = 7
}

variable "alert_email" {
  description = "Address receiving WAF alarms. Supplied by the global HCP variable set `shared-alert-email` -- do not set it in a committed tfvars file."
  type        = string
  sensitive   = true
}

variable "blocked_requests_threshold" {
  description = "BlockedRequests in 5 minutes before alarming."
  type        = number
  default     = 50
}

variable "counted_requests_threshold" {
  description = "CountedRequests in 5 minutes before alarming."
  type        = number
  default     = 50
}
