variable "project" {
  type    = string
  default = "fleet-mgmt"
}
variable "environment" {
  type    = string
  default = "dev"
}
variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "vpc_cidr" {
  type    = string
  default = "10.3.0.0/16"
}
variable "instance_type" {
  type    = string
  default = "t3.micro"
}
variable "desired_capacity" {
  type    = number
  default = 2
}
variable "min_size" {
  type    = number
  default = 1
}
variable "max_size" {
  type    = number
  default = 4
}
variable "alert_email" {
  type = string
}
variable "webhook_secret" {
  type      = string
  sensitive = true
}
variable "servicenow_instance_url" {
  type = string
}
variable "servicenow_username" {
  type = string
}
variable "servicenow_password" {
  type      = string
  sensitive = true
}
