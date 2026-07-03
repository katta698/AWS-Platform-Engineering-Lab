variable "project" {
  type        = string
  description = "Project name used in resource naming"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod)"
}

variable "account_id" {
  type        = string
  description = "AWS account ID — used to make bucket name globally unique"
}

variable "sqs_queue_arn" {
  type        = string
  description = "ARN of the SQS queue that receives S3 object-created notifications"
}

variable "intelligent_tiering_archive_days" {
  type        = number
  default     = 90
  description = "Days of no access before IT moves objects to Archive Instant Access tier"
}

variable "intelligent_tiering_deep_archive_days" {
  type        = number
  default     = 180
  description = "Days of no access before IT moves objects to Deep Archive Access tier"
}

variable "logs_ia_transition_days" {
  type        = number
  default     = 30
  description = "Days before logs/ objects transition to Standard-IA (minimum 30 to avoid early-deletion fees)"
}

variable "logs_glacier_transition_days" {
  type        = number
  default     = 90
  description = "Days before logs/ objects transition to Glacier Instant Retrieval"
}

variable "logs_expiration_days" {
  type        = number
  default     = 365
  description = "Days before logs/ objects are permanently deleted"
}

variable "noncurrent_version_expiration_days" {
  type        = number
  default     = 30
  description = "Days before non-current object versions are deleted (versioning cleanup)"
}
