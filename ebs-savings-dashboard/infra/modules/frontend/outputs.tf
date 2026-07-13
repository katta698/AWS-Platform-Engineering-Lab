output "cloudfront_domain" { value = aws_cloudfront_distribution.frontend.domain_name }
output "cloudfront_id" { value = aws_cloudfront_distribution.frontend.id }
output "bucket_name" { value = aws_s3_bucket.frontend.bucket }
