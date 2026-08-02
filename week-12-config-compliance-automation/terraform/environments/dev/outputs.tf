output "config_recorder_name" {
  description = "Name of this Lab's own Config recorder (provisioned 2026-07-29 after the account's previous, unrelated-project-owned recorder was deleted)."
  value       = module.config_recorder.recorder_name
}

output "config_recorder_bucket" {
  description = "S3 bucket Config delivers configuration history/snapshots to."
  value       = module.config_recorder.delivery_bucket_name
}
