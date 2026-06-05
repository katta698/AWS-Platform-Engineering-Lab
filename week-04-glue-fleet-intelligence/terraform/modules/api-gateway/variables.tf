variable "project_name"          { type = string }
variable "environment"           { type = string }
variable "webhook_receiver_arn"  { type = string }
variable "webhook_receiver_name" { type = string }
variable "tags"                  { type = map(string) default = {} }
