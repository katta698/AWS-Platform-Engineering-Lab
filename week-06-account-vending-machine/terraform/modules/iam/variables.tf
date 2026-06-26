variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "state_machine_arn" {
  type = string
}

variable "lambda_arns" {
  description = "Map of lambda_name => arn, for the Step Functions invoke policy"
  type        = map(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
