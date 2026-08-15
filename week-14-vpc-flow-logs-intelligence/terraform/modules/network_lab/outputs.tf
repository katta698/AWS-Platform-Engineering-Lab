output "vpc_id" {
  description = "ID of the observed VPC. The flow log subscription attaches here."
  value       = aws_vpc.this.id
}

output "public_subnet_id" {
  description = "Public subnet ID."
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Private subnet ID."
  value       = aws_subnet.private.id
}

output "nat_gateway_id" {
  description = "NAT gateway ID -- useful when correlating billed egress against flow records."
  value       = aws_nat_gateway.this.id
}

output "nat_public_ip" {
  description = "Public IP of the NAT gateway. Every NAT-path flow leaves from this address."
  value       = aws_eip.nat.public_ip
}

output "s3_endpoint_id" {
  description = "S3 gateway endpoint ID -- the free path in the traffic-path contrast."
  value       = aws_vpc_endpoint.s3.id
}

output "generator_instance_id" {
  description = "Traffic generator instance ID."
  value       = aws_instance.generator.id
}

output "generator_private_ip" {
  description = "Private IP of the generator. This is the srcaddr on NAT-bound flows before translation."
  value       = aws_instance.generator.private_ip
}

output "exposed_instance_id" {
  description = "Exposed instance ID, or null when disabled."
  value       = var.enable_exposed_instance ? aws_instance.exposed[0].id : null
}

output "exposed_public_ip" {
  description = "Public IP of the exposed instance. Unsolicited traffic to this address becomes REJECT records."
  value       = var.enable_exposed_instance ? aws_instance.exposed[0].public_ip : null
}
