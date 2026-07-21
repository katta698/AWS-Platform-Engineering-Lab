variable "name_prefix" {
  description = "Prefix for all remediation resource names."
  type        = string
}

variable "alert_email" {
  description = "Email address subscribed to the SNS alerts topic (needs manual confirmation)."
  type        = string
  sensitive   = true
}

variable "remediation_tag_key" {
  description = "Opt-in tag key: only resources carrying this tag are auto-remediated."
  type        = string
  default     = "auto-remediate"
}

variable "remediation_tag_value" {
  description = "Opt-in tag value required for auto-remediation."
  type        = string
  default     = "true"
}

variable "high_risk_ports" {
  description = "Comma-separated ports the SG remediator revokes world-open ingress for."
  type        = string
  default     = "22,3389"
}

variable "guardduty_min_severity" {
  description = "GuardDuty findings below this numeric severity are not notified (1.0-3.9 Low, 4.0-6.9 Medium, 7.0+ High)."
  type        = string
  default     = "4.0"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for the remediation Lambdas."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to remediation resources."
  type        = map(string)
  default     = {}
}
