output "api_gateway_url" {
  description = "ServiceNow webhook endpoint"
  value       = module.api_gateway.api_url
}

output "state_machine_arn" {
  value = module.step_functions.state_machine_arn
}

output "alb_dns_name" {
  description = "Shared ALB DNS name — every self-service URL is http://<this>/<service-name>/"
  value       = module.alb.alb_dns_name
}

output "cluster_name" {
  value = module.ecs_cluster.cluster_name
}
