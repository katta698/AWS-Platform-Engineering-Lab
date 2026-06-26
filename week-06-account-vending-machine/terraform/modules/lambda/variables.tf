variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "webhook_receiver_role_arn" {
  type = string
}

variable "account_creator_role_arn" {
  type = string
}

variable "account_mover_role_arn" {
  type = string
}

variable "status_notifier_role_arn" {
  type = string
}

variable "state_machine_arn" {
  type = string
}

variable "root_id" {
  description = "Organizations root ID — SourceParentId for move_account"
  type        = string
}

variable "ou_ids_json" {
  description = "JSON-encoded map of OU name to OU ID, injected into webhook_receiver"
  type        = string
}

# SSM parameter names (created in environment main.tf)
variable "hmac_secret_param" {
  type = string
}

variable "snow_instance_param" {
  type = string
}

variable "snow_user_param" {
  type = string
}

variable "snow_password_param" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
