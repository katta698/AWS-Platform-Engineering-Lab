variable "project" {
  type        = string
  description = "Project name used in resource naming"
}

variable "environment" {
  type        = string
  description = "Deployment environment"
}

variable "aws_region" {
  type        = string
  description = "AWS region"
}

variable "bucket_name" {
  type        = string
  description = "Name of the S3 bucket being monitored (passed to reporter Lambda as env var)"
}

variable "bucket_arn" {
  type        = string
  description = "ARN of the S3 bucket — used to scope object_tagger IAM permissions"
}

variable "sns_email" {
  type        = string
  description = "Email address for daily storage cost report delivery"
}

variable "reporter_schedule" {
  type        = string
  default     = "rate(1 day)"
  description = "EventBridge schedule expression for the daily cost reporter"
}
