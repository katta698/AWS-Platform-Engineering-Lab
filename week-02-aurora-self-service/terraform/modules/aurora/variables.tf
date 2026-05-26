variable "project" { type = string }
variable "environment" { type = string }

variable "db_subnet_group_name" {
  description = "DB subnet group for Aurora (from VPC module)"
  type        = string
}

variable "aurora_security_group_id" {
  description = "Security group ID attached to the Aurora cluster"
  type        = string
}

variable "master_username" {
  description = "Master DB username"
  type        = string
  default     = "dbadmin"
}

variable "master_password" {
  description = "Master DB password — pulled from Secrets Manager at apply time"
  type        = string
  sensitive   = true
}

variable "database_name" {
  description = "Initial database created on the cluster"
  type        = string
  default     = "selfservice"
}

variable "min_capacity" {
  description = "Aurora Serverless v2 minimum ACUs (0.5 = scales to near-zero)"
  type        = number
  default     = 0.5
}

variable "max_capacity" {
  description = "Aurora Serverless v2 maximum ACUs"
  type        = number
  default     = 16
}

variable "backup_retention_days" {
  description = "Automated backup retention in days"
  type        = number
  default     = 7
}

variable "performance_insights_retention_days" {
  description = "Performance Insights retention (7 = free tier)"
  type        = number
  default     = 7
}

variable "alert_sns_topic_arn" {
  description = "SNS topic ARN for CloudWatch alarms"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
