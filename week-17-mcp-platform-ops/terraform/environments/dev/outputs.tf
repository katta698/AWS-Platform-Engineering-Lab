output "mcp_endpoint" {
  description = "MCP Streamable HTTP endpoint. Requires SigV4; unsigned requests get 403."
  value       = module.mcp_server.function_url
}

output "function_name" {
  value = module.mcp_server.function_name
}

output "server_role_arn" {
  description = "Read-only role the server assumes."
  value       = module.mcp_server.role_arn
}

output "cache_table_name" {
  value = module.mcp_server.cache_table_name
}

output "alarm_name" {
  value = module.mcp_server.alarm_name
}
