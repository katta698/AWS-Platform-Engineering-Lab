variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "state_machine_arn" {
  type = string
}

variable "lambda_arns" {
  type = map(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
