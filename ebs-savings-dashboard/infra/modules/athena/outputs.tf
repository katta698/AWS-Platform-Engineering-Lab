output "workgroup_name" { value = aws_athena_workgroup.ebs_savings.name }
output "workgroup_arn" { value = aws_athena_workgroup.ebs_savings.arn }
output "database_name" { value = aws_glue_catalog_database.cur.name }
output "results_bucket_name" { value = aws_s3_bucket.results.bucket }
output "results_bucket_arn" { value = aws_s3_bucket.results.arn }
