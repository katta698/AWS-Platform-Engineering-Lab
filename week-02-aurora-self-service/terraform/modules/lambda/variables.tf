variable "project" { type = string }
variable "environment" { type = string }

variable "vpc_id" { type = string }
variable "subnet_ids" { type = list(string) }
variable "security_group_id" { type = string }

variable "state_machine_arn" { type = string }
variable "master_secret_arn" { type = string }
variable "rotation_lambda_arn" { type = string }
variable "cluster_endpoint" { type = string }
variable "cluster_reader_endpoint" { type = string }

variable "webhook_secret_param" { type = string }
variable "servicenow_instance_param" { type = string }
variable "servicenow_username_param" { type = string }
variable "servicenow_password_param" { type = string }

variable "pg8000_layer_arn" {
  description = "ARN of Lambda layer containing pg8000 library"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
