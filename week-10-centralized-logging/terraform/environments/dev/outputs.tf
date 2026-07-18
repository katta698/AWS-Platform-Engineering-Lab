output "oam_sink_arn" {
  description = "OAM sink source accounts link to"
  value       = module.oam_hub.sink_arn
}

output "oam_link_label" {
  description = "Label the source account's shared data appears under"
  value       = module.oam_spoke.link_label
}

output "centralized_log_group" {
  description = "Log group name replicated into the monitoring account"
  value       = module.alerting.centralized_log_group_name
}

output "sns_topic_arn" {
  description = "Error-alarm notification topic"
  value       = module.alerting.sns_topic_arn
}

output "dashboard_name" {
  description = "Cross-account CloudWatch dashboard"
  value       = module.alerting.dashboard_name
}
