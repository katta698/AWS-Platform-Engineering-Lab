variable "project_name"         { type = string }
variable "environment"          { type = string }
variable "lambda_role_arn"      { type = string }
variable "state_machine_arn"    { type = string }
variable "crawler_name"         { type = string }
variable "etl_job_name"         { type = string }
variable "athena_workgroup_name" { type = string }

# SSM parameter names (created in environment main.tf)
variable "hmac_secret_param"   { type = string }
variable "snow_instance_param" { type = string }
variable "snow_user_param"     { type = string }
variable "snow_password_param" { type = string }

variable "tags" { type = map(string) default = {} }
