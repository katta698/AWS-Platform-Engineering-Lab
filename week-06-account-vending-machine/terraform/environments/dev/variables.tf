variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "project_name" {
  type    = string
  default = "jay-account-vending"
}

# ── ServiceNow ────────────────────────────────────────────────────────────────
variable "servicenow_instance" {
  description = "ServiceNow instance name (e.g. dev388443 — without .service-now.com)"
  type        = string
  sensitive   = true
}

variable "servicenow_username" {
  type      = string
  sensitive = true
}

variable "servicenow_password" {
  type      = string
  sensitive = true
}

# ── Webhook HMAC secret ───────────────────────────────────────────────────────
variable "webhook_secret" {
  description = "HMAC-SHA256 secret for ServiceNow webhook signature validation"
  type        = string
  sensitive   = true
}

# ── Organizations guardrails ───────────────────────────────────────────────────
variable "parent_ou_name" {
  description = "Name of the existing root-level OU to nest the vending OUs under (this Organization already has Core-OU/Archived-Accounts/Workloads-OU at root from a prior Control Tower setup — vending OUs should not sit alongside those)"
  type        = string
  default     = "Workloads-OU"
}

variable "ou_names" {
  description = "OUs to create for vended accounts"
  type        = list(string)
  default     = ["Sandbox", "Production"]
}

variable "allowed_regions" {
  description = "Regions allowed inside the Sandbox OU SCP"
  type        = list(string)
  default     = ["us-east-1"]
}
