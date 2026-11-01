# ── Core ──────────────────────────────────────────────────────────────────────
variable "aws_region" {
  description = "Primary AWS region for all resources (except CUR which is always us-east-1)"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Deployment environment tag (dev / staging / prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod"
  }
}

variable "org_name" {
  description = "Short org slug used in resource names (lowercase, no spaces)"
  type        = string
}

variable "org_id" {
  description = "AWS Organizations ID (o-xxxxxxxxxx) — used to scope cross-account role trust"
  type        = string
  default     = "" # leave empty if not using AWS Organizations
}

variable "member_account_ids" {
  description = "List of member account IDs to deploy the cross-account read role into"
  type        = list(string)
  default     = []
}

# ── Bootstrap ─────────────────────────────────────────────────────────────────
variable "bootstrap_state_bucket" {
  description = "Set true on first run to create the S3 + DynamoDB state backend resources"
  type        = bool
  default     = false
}

# ── Networking ────────────────────────────────────────────────────────────────
variable "vpc_id" {
  description = "VPC ID for Lambda. Leave empty to deploy Lambda outside a VPC (simpler for dev)"
  type        = string
  default     = ""
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for Lambda VPC placement (required when vpc_id is set)"
  type        = list(string)
  default     = []
}

# ── Frontend / DNS ────────────────────────────────────────────────────────────
variable "domain_name" {
  description = "Custom domain for the dashboard (e.g. ebs-savings.internal.example.com). Leave empty to use CloudFront default domain."
  type        = string
  default     = ""
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN in us-east-1 for the custom domain. Required when domain_name is set."
  type        = string
  default     = ""
}

# ── Auth ──────────────────────────────────────────────────────────────────────
variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID for API JWT authorizer. Leave empty to use IAM auth (easier for testing)."
  type        = string
  default     = ""
}

variable "cognito_app_client_id" {
  description = "Cognito App Client ID paired with the user pool above."
  type        = string
  default     = ""
}

# ── Athena ────────────────────────────────────────────────────────────────────
variable "athena_scan_limit_bytes" {
  description = "Maximum bytes a single Athena query can scan (safety limit). Default 10 GB."
  type        = number
  default     = 10737418240
}
