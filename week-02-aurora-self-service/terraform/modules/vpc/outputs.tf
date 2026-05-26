output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  value = aws_subnet.database[*].id
}

output "aurora_security_group_id" {
  value = aws_security_group.aurora.id
}

output "lambda_security_group_id" {
  value = aws_security_group.lambda.id
}

output "db_subnet_group_name" {
  value = aws_db_subnet_group.aurora.name
}
