output "bucket_name" {
  description = "Name of the flow logs bucket."
  value       = aws_s3_bucket.flow_logs.id
}

output "bucket_arn" {
  description = "ARN of the flow logs bucket."
  value       = aws_s3_bucket.flow_logs.arn
}

output "flow_log_id" {
  description = "ID of the flow log subscription. Appears in every delivered object's filename."
  value       = aws_flow_log.this.id
}

output "delivery_role_arn" {
  description = "ARN of the flow log delivery role."
  value       = aws_iam_role.flow_logs.arn
}

output "s3_prefix" {
  description = <<-EOT
    The hive-compatible prefix flow logs are delivered under, up to the point where
    partitioning begins. The Glue table's location template is built from this.
  EOT
  value       = "AWSLogs/aws-account-id=${data.aws_caller_identity.current.account_id}/aws-service=vpcflowlogs"
}
