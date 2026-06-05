output "api_gateway_url" {
  description = "ServiceNow webhook endpoint"
  value       = module.api_gateway.api_url
}

output "raw_bucket_name" {
  value = module.s3.raw_bucket_name
}

output "curated_bucket_name" {
  value = module.s3.curated_bucket_name
}

output "crawler_name" {
  value = module.glue.crawler_name
}

output "etl_job_name" {
  value = module.glue.etl_job_name
}

output "athena_workgroup" {
  value = module.glue.athena_workgroup_name
}

output "state_machine_arn" {
  value = module.step_functions.state_machine_arn
}

output "state_machine_name" {
  value = module.step_functions.state_machine_name
}
