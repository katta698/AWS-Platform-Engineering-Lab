variable "name" { type = string }
variable "region" { type = string }
variable "account_id" { type = string }
variable "cluster_name" { type = string }
variable "service_name" { type = string }

variable "fault_percent" {
  type        = number
  description = "Share of tasks to stop. 50 degrades the service without taking it down, which is the realistic case; 100 is an outage and tells you less."
  default     = 50
}

variable "stop_condition_alarms" {
  type        = map(string)
  description = "name -> alarm ARN. One guarded experiment per entry, identical except for the alarm."
}

variable "tags" {
  type    = map(string)
  default = {}
}
