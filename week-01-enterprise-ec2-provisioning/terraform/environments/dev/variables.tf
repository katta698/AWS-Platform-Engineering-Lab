###############################################################################
# Dev Environment Variables
###############################################################################

variable "project" {
  type    = string
  default = "selfservice-ec2"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cost_center" {
  type    = string
  default = "platform-engineering"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "root_volume_size" {
  type    = number
  default = 30
}

variable "asg_min_size" {
  type    = number
  default = 1
}

variable "asg_max_size" {
  type    = number
  default = 4
}

variable "asg_desired_capacity" {
  type    = number
  default = 2
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "artifact_bucket_name" {
  type        = string
  description = "S3 bucket for app artifacts"
}

variable "tf_state_bucket" {
  type        = string
  description = "S3 bucket for Terraform remote state"
}

variable "github_org" {
  type        = string
  description = "GitHub organization name"
}

variable "github_repo" {
  type        = string
  description = "GitHub repository name"
}

variable "create_github_oidc_provider" {
  type    = bool
  default = true
}

variable "existing_oidc_provider_arn" {
  type    = string
  default = ""
}

variable "alert_emails" {
  type    = list(string)
  default = []
}

# Written by ServiceNow Lambda before Terraform apply — enables ticket tracing
variable "servicenow_ticket_id" {
  type    = string
  default = ""
}

# ServiceNow integration credentials (stored in SSM)
variable "servicenow_instance_url" {
  type        = string
  description = "ServiceNow instance URL e.g. https://dev388443.service-now.com"
}

variable "servicenow_username" {
  type        = string
  description = "ServiceNow API username"
}

variable "servicenow_password" {
  type        = string
  sensitive   = true
  description = "ServiceNow API password"
}

variable "github_token" {
  type        = string
  sensitive   = true
  description = "GitHub Personal Access Token with repo scope for repository_dispatch"
}

variable "webhook_secret" {
  type        = string
  sensitive   = true
  description = "HMAC secret for validating ServiceNow webhook signatures"
  default     = "dev-webhook-secret-change-in-prod"
}
