output "app_repository_url" {
  description = "Push signed-and-scanned images here."
  value       = module.image_pipeline.app_repository_url
}

output "outside_filter_repository_url" {
  description = "Control group: proves the repository filter is real."
  value       = module.image_pipeline.outside_filter_repository_url
}

output "signing_profile_name" {
  value = module.image_pipeline.signing_profile_name
}

output "gate_function_name" {
  value = module.image_pipeline.gate_function_name
}

output "gate_log_group" {
  value = module.image_pipeline.gate_log_group
}

output "quarantine_topic_arn" {
  value = module.image_pipeline.quarantine_topic_arn
}

output "build_project_name" {
  description = "Start this to build and push the test images."
  value       = module.image_pipeline.build_project_name
}
