variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "ec2_sg_id" {
  type = string
}

variable "target_group_arn" {
  type = string
}

variable "instance_profile_name" {
  type = string
}

variable "ami_id" {
  type    = string
  default = ""
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "root_volume_size" {
  type    = number
  default = 20
}

variable "app_port" {
  type    = number
  default = 8080
}

variable "min_size" {
  type    = number
  default = 1
}

variable "max_size" {
  type    = number
  default = 4
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "tags" {
  type    = map(string)
  default = {}
}
