variable "prefix" { type = string }
variable "api_invoke_url" { type = string }
variable "domain_name" {
  type    = string
  default = ""
}
variable "acm_certificate_arn" {
  type    = string
  default = ""
}
variable "use_custom_domain" {
  type    = bool
  default = false
}
