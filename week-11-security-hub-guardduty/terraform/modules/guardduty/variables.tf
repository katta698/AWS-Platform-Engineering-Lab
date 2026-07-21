variable "finding_publishing_frequency" {
  description = "How often GuardDuty exports findings to EventBridge/Security Hub. FIFTEEN_MINUTES gives a faster demo loop than the SIX_HOURS default."
  type        = string
  default     = "FIFTEEN_MINUTES"

  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.finding_publishing_frequency)
    error_message = "Must be one of FIFTEEN_MINUTES, ONE_HOUR, SIX_HOURS."
  }
}

variable "tags" {
  description = "Tags to apply to the detector."
  type        = map(string)
  default     = {}
}
