variable "name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "function_names" {
  description = "Service name -> Lambda function name, from the service module."
  type        = map(string)
}

variable "region" {
  description = "Needed by the dashboard widgets; they do not inherit it."
  type        = string
}
