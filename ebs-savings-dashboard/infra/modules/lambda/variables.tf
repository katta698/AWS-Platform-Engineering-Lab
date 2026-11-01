variable "prefix" { type = string }
variable "region" { type = string }
variable "account_id" { type = string }
variable "org_id" {
  type    = string
  default = ""
}
variable "athena_workgroup_name" { type = string }
variable "athena_workgroup_arn" { type = string }
variable "athena_database" { type = string }
variable "results_bucket_name" { type = string }
variable "results_bucket_arn" { type = string }
variable "cur_bucket_arn" { type = string }
variable "kms_key_arn" { type = string }
variable "cur_kms_key_arn" { type = string }
variable "athena_kms_key_arn" { type = string }
variable "vpc_id" {
  type    = string
  default = ""
}
variable "private_subnet_ids" {
  type    = list(string)
  default = []
}
variable "use_vpc" {
  type    = bool
  default = false
}
