variable "project" {
  description = "Project identifier used in all resource names"
  type        = string
  default     = "selfservice-db"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

# ── Aurora ────────────────────────────────────────────────────────────────────
variable "master_username" {
  type    = string
  default = "dbadmin"
}

variable "master_password" {
  description = "Aurora master password — stored in Secrets Manager post-deploy"
  type        = string
  sensitive   = true
}

variable "aurora_min_capacity" {
  type    = number
  default = 0.5
}

variable "aurora_max_capacity" {
  type    = number
  default = 16
}

# ── pg8000 Lambda Layer ───────────────────────────────────────────────────────
variable "pg8000_layer_arn" {
  description = "ARN of Lambda layer containing pg8000 (built by scripts/build_layer.sh)"
  type        = string
}

# ── Notifications ─────────────────────────────────────────────────────────────
variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
}

# ── ServiceNow / GitHub ───────────────────────────────────────────────────────
variable "servicenow_instance_url" {
  type      = string
  sensitive = true
}

variable "servicenow_username" {
  type      = string
  sensitive = true
}

variable "servicenow_password" {
  type      = string
  sensitive = true
}

variable "webhook_secret" {
  type      = string
  sensitive = true
}

variable "github_org" { type = string }
variable "github_repo" { type = string }
variable "github_token" {
  type      = string
  sensitive = true
}

variable "create_github_oidc_provider" {
  type    = bool
  default = false
}

variable "existing_oidc_provider_arn" {
  type    = string
  default = ""
}
