output "recorder_name" {
  description = "Name of the Config recorder."
  value       = aws_config_configuration_recorder.this.name
}

output "delivery_bucket_name" {
  description = "S3 bucket Config delivers configuration history/snapshots to."
  value       = aws_s3_bucket.config.id
}

output "recorder_role_arn" {
  description = "IAM role the recorder assumes."
  value       = aws_iam_role.config_recorder.arn
}
