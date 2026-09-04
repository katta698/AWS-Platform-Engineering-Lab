variable "name_prefix" {
  description = "Prefix for every resource name in this module."
  type        = string
  default     = "week17"
}

variable "log_retention_days" {
  description = "CloudWatch log retention. Set explicitly because the implicit log group never expires."
  type        = number
  default     = 7
}

variable "cache_ttl_seconds" {
  description = "How long a Cost Explorer answer stays cached. Cost Explorer bills $0.01 per request, so this directly controls spend."
  type        = number
  default     = 3600
}

variable "alarm_sns_topic_arn" {
  description = "Optional SNS topic for the errors alarm. Empty means the alarm still evaluates but notifies nobody."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Extra tags merged into every resource."
  type        = map(string)
  default     = {}
}
