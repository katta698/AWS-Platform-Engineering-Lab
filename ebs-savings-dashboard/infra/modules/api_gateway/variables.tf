variable "prefix" { type = string }
variable "lambda_function_arn" { type = string }
variable "lambda_function_name" { type = string }
variable "cognito_user_pool_id" {
  type    = string
  default = ""
}
variable "cognito_app_client_id" {
  type    = string
  default = ""
}
variable "use_cognito" {
  type    = bool
  default = false
}
variable "region" { type = string }
variable "allowed_origin" {
  type    = string
  default = "*"
}
