variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.90.0.0/16"
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.90.0.0/24", "10.90.1.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.90.10.0/24", "10.90.11.0/24"]
}

variable "availability_zones" {
  type = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}
