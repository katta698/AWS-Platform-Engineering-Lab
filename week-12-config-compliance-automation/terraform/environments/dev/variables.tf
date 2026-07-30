variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for named resources across the stack."
  type        = string
  default     = "week12-cfgcompliance"
}

variable "alert_email" {
  description = "Email subscribed to the compliance digest SNS topic. Set in HCP as a sensitive variable; confirm the subscription email after first apply."
  type        = string
  sensitive   = true
}

variable "remediation_tag_key" {
  description = "Opt-in tag key gating auto-remediation (same convention as Week 11)."
  type        = string
  default     = "auto-remediate"
}

variable "remediation_tag_value" {
  description = "Opt-in tag value gating auto-remediation."
  type        = string
  default     = "true"
}

variable "required_tag_keys" {
  description = "Exactly 3 tag keys the required-tags rule enforces."
  type        = list(string)
  default     = ["environment", "owner", "cost-center"]

  validation {
    condition     = length(var.required_tag_keys) == 3
    error_message = "required_tag_keys must contain exactly 3 keys -- the conformance pack template hardcodes tag1Key/tag2Key/tag3Key."
  }
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the reporter Lambda."
  type        = number
  default     = 30
}
