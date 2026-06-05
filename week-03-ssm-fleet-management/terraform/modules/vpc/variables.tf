variable "project"     { type = string }
variable "environment" { type = string }
variable "vpc_cidr" {
  type    = string
  default = "10.3.0.0/16"
}
