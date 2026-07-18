variable "rule_name" {
  type = string
}

variable "organization_id" {
  type = string
}

variable "source_region" {
  type = string
}

variable "destination_account_id" {
  type = string
}

variable "destination_region" {
  type = string
}

variable "log_group_prefix" {
  description = "Only log groups whose names start with this prefix are centralized"
  type        = string
}
