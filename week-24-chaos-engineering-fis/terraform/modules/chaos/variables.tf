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

# Seven rounds two minutes apart = a twelve-minute experiment, 13 actions
# (7 kills + 6 waits) against a quota of 20 actions per template.
#
# The duration is chosen so the SLOW alarm can still fire: 2 datapoints of
# 300s needs 600s of breaching data, so a twelve-minute fault leaves it room
# to trip at roughly ten and a half minutes. Make this shorter and the typical
# alarm simply never fires -- a true result, but a weaker one than a measured
# delta between the two.
variable "kill_rounds" {
  description = "How many times the fault is injected during one experiment."
  type        = number
  default     = 7
}

variable "round_gap" {
  description = "ISO 8601 wait between kill rounds. aws:fis:wait has a one-minute floor."
  type        = string
  default     = "PT2M"
}
