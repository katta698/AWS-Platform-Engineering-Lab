variable "name_prefix" {
  description = "Prefix for named resources in this module."
  type        = string
}

variable "alert_email" {
  description = "Email subscribed to the compliance digest SNS topic."
  type        = string
  sensitive   = true
}

variable "conformance_pack_name" {
  description = "Conformance pack the reporter Lambda discovers rules from -- deliberately just this week's own pack, not the account's ~300 securityhub-* rules."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the reporter Lambda."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Common tags applied to every resource this module creates."
  type        = map(string)
}
