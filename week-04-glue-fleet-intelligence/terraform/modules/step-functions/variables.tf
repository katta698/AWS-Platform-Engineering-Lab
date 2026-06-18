variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "sfn_role_arn" {
  type = string
}

variable "glue_trigger_lambda_arn" {
  type = string
}

variable "status_updater_lambda_arn" {
  type = string
}

variable "crawler_name" {
  type = string
}

variable "etl_job_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
