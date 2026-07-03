variable "project" {
  type        = string
  default     = "week-08-s3-storage"
  description = "Project name prefix for all resources"
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Deployment environment"
}

variable "aws_region" {
  type        = string
  default     = "us-east-1"
  description = "AWS region for all resources"
}

variable "sns_email" {
  type        = string
  description = "Email address to receive daily storage cost reports"
}

variable "intelligent_tiering_archive_days" {
  type        = number
  default     = 90
  description = "Days of inactivity before objects move to Archive Instant Access"
}

variable "intelligent_tiering_deep_archive_days" {
  type        = number
  default     = 180
  description = "Days of inactivity before objects move to Deep Archive Access"
}

variable "logs_ia_transition_days" {
  type    = number
  default = 30
}

variable "logs_glacier_transition_days" {
  type    = number
  default = 90
}

variable "logs_expiration_days" {
  type    = number
  default = 365
}

variable "noncurrent_version_expiration_days" {
  type    = number
  default = 30
}
