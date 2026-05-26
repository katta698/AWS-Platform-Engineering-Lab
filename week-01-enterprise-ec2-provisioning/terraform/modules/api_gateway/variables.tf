variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "lambda_invoke_arn" {
  type        = string
  description = "Invoke ARN of the servicenow_receiver Lambda"
}

variable "tags" {
  type    = map(string)
  default = {}
}
