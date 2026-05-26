variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "state_machine_arn" {
  type        = string
  description = "Step Functions state machine ARN for servicenow_receiver to start executions"
}

variable "api_gateway_execution_arn" {
  type        = string
  description = "API Gateway execution ARN for Lambda permission"
}

variable "github_org" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}
