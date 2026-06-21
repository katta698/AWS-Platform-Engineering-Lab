variable "project"             { type = string }
variable "environment"         { type = string }
variable "raw_sns_topic_arn"   { type = string }
variable "alert_sns_topic_arn" { type = string }
variable "log_retention_days"  { type = number }
variable "tags"                { type = map(string) }
