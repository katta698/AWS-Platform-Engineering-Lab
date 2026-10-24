output "alb_url" {
  description = "Hit this to confirm the service is actually serving before breaking it."
  value       = "http://${module.service.alb_dns}"
}

output "cluster_name" { value = module.service.cluster_name }
output "service_name" { value = module.service.service_name }

output "alarms" {
  value = {
    fast    = module.service.alarm_fast_name
    typical = module.service.alarm_typical_name
  }
}

output "experiments" {
  description = "Label -> FIS experiment template id."
  value       = module.chaos.experiment_ids
}

output "fis_log_group" { value = module.chaos.log_group }
