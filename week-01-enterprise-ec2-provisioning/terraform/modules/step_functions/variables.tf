variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "status_updater_arn" {
  type        = string
  description = "ARN of the status_updater Lambda function"
}

variable "deployment_trigger_arn" {
  type        = string
  description = "ARN of the deployment_trigger Lambda function"
}

variable "tags" {
  type    = map(string)
  default = {}
}
