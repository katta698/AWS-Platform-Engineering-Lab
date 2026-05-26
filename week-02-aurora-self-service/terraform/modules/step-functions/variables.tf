variable "project" { type = string }
variable "environment" { type = string }

variable "db_provisioner_arn" { type = string }
variable "status_updater_arn" { type = string }
variable "cluster_reader_endpoint" { type = string }

variable "alert_sns_topic_arn" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}
