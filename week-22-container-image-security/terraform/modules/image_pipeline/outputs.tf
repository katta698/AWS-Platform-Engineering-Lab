output "app_repository_url" {
  description = "Push target for the signed-and-scanned repository."
  value       = aws_ecr_repository.app.repository_url
}

output "app_repository_name" {
  value = aws_ecr_repository.app.name
}

output "outside_filter_repository_url" {
  description = "Control group: outside the signing and scanning filters."
  value       = aws_ecr_repository.outside_filter.repository_url
}

output "outside_filter_repository_name" {
  value = aws_ecr_repository.outside_filter.name
}

output "signing_profile_name" {
  value = aws_signer_signing_profile.images.name
}

output "signing_profile_arn" {
  value = aws_signer_signing_profile.images.arn
}

output "gate_function_name" {
  value = aws_lambda_function.gate.function_name
}

output "gate_log_group" {
  value = aws_cloudwatch_log_group.gate.name
}

output "quarantine_topic_arn" {
  value = aws_sns_topic.quarantine.arn
}
