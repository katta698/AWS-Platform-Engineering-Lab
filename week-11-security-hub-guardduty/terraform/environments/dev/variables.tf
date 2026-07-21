variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix for named resources across the stack."
  type        = string
  default     = "week11-secrem"
}

variable "alert_email" {
  description = "Email subscribed to the SNS alerts topic. Set in HCP as a sensitive variable; confirm the subscription email after first apply."
  type        = string
  sensitive   = true
}

variable "finding_publishing_frequency" {
  description = "GuardDuty finding export cadence."
  type        = string
  default     = "FIFTEEN_MINUTES"
}

variable "remediation_tag_key" {
  description = "Opt-in tag key gating auto-remediation."
  type        = string
  default     = "auto-remediate"
}

variable "remediation_tag_value" {
  description = "Opt-in tag value gating auto-remediation."
  type        = string
  default     = "true"
}

variable "high_risk_ports" {
  description = "Comma-separated ports the SG remediator closes to the world."
  type        = string
  default     = "22,3389"
}

variable "guardduty_min_severity" {
  description = "Minimum GuardDuty severity that triggers an SNS notification."
  type        = string
  default     = "4.0"
}

variable "production_tag_key" {
  description = "Tag key marking a resource production (severity escalation)."
  type        = string
  default     = "environment"
}

variable "production_tag_value" {
  description = "Tag value marking a resource production."
  type        = string
  default     = "production"
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention for remediation Lambdas."
  type        = number
  default     = 30
}
