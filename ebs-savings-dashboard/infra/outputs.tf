output "cloudfront_url" {
  description = "Dashboard URL — open this in your browser"
  value       = "https://${module.frontend.cloudfront_domain}"
}

output "api_invoke_url" {
  description = "API Gateway base URL — set as VITE_API_URL in .env.local"
  value       = module.api_gateway.invoke_url
}

output "cur_bucket_name" {
  description = "S3 bucket receiving CUR 2.0 reports"
  value       = module.cur.bucket_name
}

output "athena_workgroup" {
  description = "Athena workgroup name"
  value       = module.athena.workgroup_name
}

output "lambda_function_name" {
  description = "Lambda function name (for CloudWatch logs)"
  value       = module.lambda.function_name
}

output "frontend_bucket_name" {
  description = "S3 bucket for the React build — run 'aws s3 sync dist/ s3://<bucket>' after build"
  value       = module.frontend.bucket_name
}
