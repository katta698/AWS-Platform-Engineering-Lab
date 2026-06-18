variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "raw_bucket_arn" {
  type = string
}

variable "curated_bucket_arn" {
  type = string
}

variable "state_machine_arn" {
  type = string
}

variable "lambda_glue_trigger_arn" {
  type = string
}

variable "lambda_status_updater_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
