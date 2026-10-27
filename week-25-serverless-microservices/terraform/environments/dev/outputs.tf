output "api_endpoint" {
  value = module.service.api_endpoint
}

output "function_names" {
  value = module.service.function_names
}

output "region" {
  value = var.region
}

output "alarms" {
  value = module.experiment.alarm_names
}

output "dashboard" {
  value = module.experiment.dashboard_name
}

output "protect_checkout" {
  description = "Which run this state represents."
  value       = var.protect_checkout
}
