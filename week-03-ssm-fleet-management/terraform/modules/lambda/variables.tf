variable "project"                  { type = string }
variable "environment"              { type = string }
variable "lambda_role_arn"          { type = string }
variable "state_machine_arn"        { type = string }
variable "webhook_secret" {
  type      = string
  sensitive = true
}
variable "servicenow_instance_url" { type = string }
variable "servicenow_username"     { type = string }
variable "servicenow_password" {
  type      = string
  sensitive = true
}
variable "ssm_automation_role_arn"  { type = string }
variable "onboard_document_name"   { type = string }
variable "patch_fleet_document_name" { type = string }
