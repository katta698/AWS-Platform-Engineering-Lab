output "url" {
  description = "curl this in a loop during a deployment to watch the version change."
  value       = "http://${module.service.alb_dns_name}/"
}

output "cluster_name" { value = module.service.cluster_name }
output "service_name" { value = module.service.service_name }
output "alarm_name" { value = module.service.alarm_name }
