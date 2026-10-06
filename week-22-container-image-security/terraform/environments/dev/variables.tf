variable "region" {
  description = "AWS region. Signer signing profiles must be in the same region as the registry -- cross-region signing is not supported."
  type        = string
  default     = "us-east-1"
}

variable "filter_prefix" {
  description = "Repository prefix that gets signed and scanned. Narrow on purpose: Inspector bills per image."
  type        = string
  default     = "wk22"
}

variable "alert_email" {
  description = "Where quarantine notices go. Set as an HCP workspace variable; never committed."
  type        = string
  default     = ""
  sensitive   = true
}
