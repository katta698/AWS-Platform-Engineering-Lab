variable "aws_region" {
  description = "Region for the MCP server. Cost Explorer is global but its endpoint lives in us-east-1."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "week17"
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days."
  type        = number
  default     = 7
}

variable "cache_ttl_seconds" {
  description = "Cost Explorer answer cache lifetime. Cost Explorer bills $0.01 per request."
  type        = number
  default     = 3600
}

variable "alarm_sns_topic_arn" {
  description = "Optional SNS topic ARN for the errors alarm."
  type        = string
  default     = ""
}
