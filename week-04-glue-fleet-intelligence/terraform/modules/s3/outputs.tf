output "raw_bucket_name"           { value = aws_s3_bucket.raw.bucket }
output "raw_bucket_arn"            { value = aws_s3_bucket.raw.arn }
output "curated_bucket_name"       { value = aws_s3_bucket.curated.bucket }
output "curated_bucket_arn"        { value = aws_s3_bucket.curated.arn }
output "athena_results_bucket_name" { value = aws_s3_bucket.athena_results.bucket }
output "athena_results_bucket_arn"  { value = aws_s3_bucket.athena_results.arn }
