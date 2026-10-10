variable "prefix" { type = string }
variable "cur_bucket_name" { type = string }
variable "cur_bucket_arn" { type = string }
variable "kms_key_arn" { type = string }
variable "scan_limit_bytes" {
  type    = number
  default = 10737418240
}
