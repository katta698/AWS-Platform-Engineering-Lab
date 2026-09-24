variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "bus_name" {
  description = "Custom bus name, also used as the prefix for every resource this week creates -- so cleanup.sh can sweep on one string."
  type        = string
  default     = "week20-bus"
}

variable "archive_retention_days" {
  description = "1 day proves replay works. Archive storage at $0.023/GB/month is the ONLY standing charge in this week."
  type        = number
  default     = 1
}

variable "log_retention_days" {
  type    = number
  default = 1
}

variable "alert_email" {
  description = <<-EOT
    Supplied automatically by the org-wide `shared-alert-email` HCP variable set
    (varset-tUUc8wv4i2MATMtH). Declared here because a variable set supplies the
    VALUE -- each configuration still has to declare the variable itself.
  EOT
  type        = string
  default     = ""
  sensitive   = true
}
