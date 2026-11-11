output "cache_endpoint" {
  value = aws_elasticache_serverless_cache.valkey.endpoint[0].address
}

output "cache_name" {
  value = aws_elasticache_serverless_cache.valkey.name
}

output "client_function" {
  value = aws_lambda_function.client.function_name
}
