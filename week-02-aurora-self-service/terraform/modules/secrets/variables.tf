variable "project" { type = string }
variable "environment" { type = string }

variable "cluster_endpoint" {
  description = "Aurora writer endpoint"
  type        = string
}

variable "cluster_port" {
  description = "Aurora port (5432 for PostgreSQL)"
  type        = number
  default     = 5432
}

variable "master_username" {
  description = "Aurora master username"
  type        = string
}

variable "master_password" {
  description = "Aurora master password"
  type        = string
  sensitive   = true
}

variable "database_name" {
  description = "Default database name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID — used to scope rotation Lambda"
  type        = string
}

variable "lambda_subnet_ids" {
  description = "Private subnet IDs for the rotation Lambda"
  type        = list(string)
}

variable "lambda_security_group_id" {
  description = "Security group ID for the rotation Lambda"
  type        = string
}

variable "rotation_days" {
  description = "Rotate master credentials every N days"
  type        = number
  default     = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
