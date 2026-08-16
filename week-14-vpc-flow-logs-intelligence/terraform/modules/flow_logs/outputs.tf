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

# No delivery_role_arn output: S3-destination flow logs do not use one, and the
# tag fields are served by the auto-created AWSServiceRoleForVPCFlowLogs
# service-linked role. See the note in main.tf.

output "s3_prefix" {
  description = <<-EOT
    The hive-compatible prefix flow logs are delivered under, up to the point where
    partitioning begins. The Glue table's location template is built from this.
  EOT
  value       = "AWSLogs/aws-account-id=${data.aws_caller_identity.current.account_id}/aws-service=vpcflowlogs"
}
