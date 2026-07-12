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
  default = "fargate-selfservice"
}

variable "availability_zones" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

# ── ServiceNow ───────────────────────────────────────────────────────────
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

# ── Webhook HMAC secret ───────────────────────────────────────────────────
variable "webhook_secret" {
  description = "HMAC-SHA256 secret for ServiceNow webhook signature validation"
  type        = string
  sensitive   = true
}
