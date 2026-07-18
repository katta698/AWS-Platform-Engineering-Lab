variable "project" {
  type = string
}

variable "centralized_log_group_name" {
  description = "Name of the centralized copy in this account (identical to the source group's name)"
  type        = string
}

variable "alert_email" {
  type      = string
  sensitive = true
}

variable "source_account_id" {
  description = "Spoke account whose metrics the dashboard reads cross-account via OAM"
  type        = string
}

variable "generator_function_name" {
  type = string
}

variable "aws_region" {
  type = string
}
