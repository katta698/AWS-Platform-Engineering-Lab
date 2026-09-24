output "bus_name" {
  value = module.bus.bus_name
}

output "bus_arn" {
  value = module.bus.bus_arn
}

output "archive_name" {
  description = "Replay re-delivers to the rules that exist NOW, not the rules that existed when archived"
  value       = module.bus.archive_name
}

output "trail_name" {
  description = "Scoped by ARN to this bus only -- an unscoped data-event selector bills for every PutEvents in the account"
  value       = module.bus.trail_name
}

output "consumer_log_group" {
  description = "A matched event appears here; an unmatched one never does"
  value       = module.consumers.consumer_log_group
}

output "catch_all_log_group" {
  value = module.consumers.catch_all_log_group
}

output "dlq_url" {
  value = module.consumers.dlq_url
}

output "unmatched_alarm_name" {
  value = module.consumers.unmatched_alarm_name
}

output "publish_matched" {
  description = "Publishes an event the orders rule matches"
  value       = "aws events put-events --entries 'Source=platform.orders,DetailType=order.created,Detail={\"orderId\":\"1\"},EventBusName=${module.bus.bus_name}'"
}

output "publish_unmatched" {
  description = "The week's whole point: this returns 200 and an EventId, and nothing consumes it"
  value       = "aws events put-events --entries 'Source=platform.orders,DetailType=order.crated,Detail={\"orderId\":\"2\"},EventBusName=${module.bus.bus_name}'"
}
