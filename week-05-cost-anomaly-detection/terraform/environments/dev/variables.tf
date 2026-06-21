variable "project" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "week05"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "alert_email" {
  description = "Email address to receive cost anomaly alerts"
  type        = string
}

variable "anomaly_threshold" {
  description = "Absolute dollar amount above expected spend that triggers an alert"
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}
