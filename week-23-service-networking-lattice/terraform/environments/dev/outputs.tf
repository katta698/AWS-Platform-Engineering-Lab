output "service_dns" {
  description = "The name the client calls. Only resolvable inside the associated VPC."
  value       = module.lattice.service_dns
}

output "service_auth_type" {
  value = module.lattice.service_auth_type
}

output "service_arn" {
  value = module.lattice.service_arn
}

output "client_function_name" {
  value = module.lattice.client_function_name
}

output "client_role_arn" {
  value = module.lattice.client_role_arn
}

output "stranger_role_arn" {
  value = module.lattice.stranger_role_arn
}

output "consumer_vpc_id" {
  value = module.lattice.consumer_vpc_id
}
