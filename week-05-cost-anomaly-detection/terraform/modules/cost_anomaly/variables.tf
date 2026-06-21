variable "project"           { type = string }
variable "environment"       { type = string }
variable "raw_sns_topic_arn" { type = string }
variable "anomaly_threshold" { type = number }
variable "tags"              { type = map(string) }
