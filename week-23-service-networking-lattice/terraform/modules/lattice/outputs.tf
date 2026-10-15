output "service_network_id" {
  value = aws_vpclattice_service_network.this.id
}

output "service_id" {
  value = aws_vpclattice_service.rates.id
}

output "service_arn" {
  value = aws_vpclattice_service.rates.arn
}

output "service_dns" {
  description = "The name the client calls. Resolvable only inside an associated VPC."
  value       = aws_vpclattice_service.rates.dns_entry[0].domain_name
}

output "service_auth_type" {
  description = "Echoed so a test can assert on it without reading the console."
  value       = aws_vpclattice_service.rates.auth_type
}

output "client_function_name" {
  value = aws_lambda_function.client.function_name
}

output "client_role_arn" {
  value = aws_iam_role.client.arn
}

output "stranger_role_arn" {
  description = "Allowed by IAM to invoke, refused by the auth policy."
  value       = aws_iam_role.stranger.arn
}

output "consumer_vpc_id" {
  value = aws_vpc.consumer.id
}

output "intruder_function_name" {
  description = "Same code, same subnets, same security group, different role."
  value       = aws_lambda_function.intruder.function_name
}
