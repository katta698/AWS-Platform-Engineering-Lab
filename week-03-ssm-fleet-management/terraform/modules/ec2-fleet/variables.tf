variable "project"              { type = string }
variable "environment"          { type = string }
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
variable "private_subnet_ids"    { type = list(string) }
variable "ec2_sg_id"             { type = string }
variable "instance_profile_name" { type = string }
