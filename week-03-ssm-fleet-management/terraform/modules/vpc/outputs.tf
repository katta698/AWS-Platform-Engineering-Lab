output "vpc_id"            { value = aws_vpc.this.id }
output "private_subnet_ids" { value = aws_subnet.private[*].id }
output "ec2_sg_id"          { value = aws_security_group.ec2.id }
output "endpoint_sg_id"     { value = aws_security_group.endpoints.id }
