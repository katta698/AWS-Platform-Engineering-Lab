output "table_name" {
  value = aws_dynamodb_table.pool.name
}

output "dax_endpoint" {
  description = "Cluster endpoint. dax:// unencrypted, daxs:// with TLS."
  value       = aws_dax_cluster.main.cluster_address
}

output "dax_node_count" {
  value = aws_dax_cluster.main.replication_factor
}

output "functions" {
  description = "principal -> function name, for the experiment script."
  value       = { for k, f in aws_lambda_function.tenant : k => f.function_name }
}

output "policies" {
  description = <<-EOT
    The three data-access policies as IAM sees them. alpha and beta carry the
    Null and Select guards; audit is the same policy without them. Emitted so
    a reader can diff the policy against the result it produced.
  EOT
  value       = local.policies
}
