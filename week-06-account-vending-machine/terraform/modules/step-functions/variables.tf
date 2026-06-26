variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "sfn_role_arn" {
  type = string
}

variable "account_creator_lambda_arn" {
  type = string
}

variable "account_mover_lambda_arn" {
  type = string
}

variable "status_notifier_lambda_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
