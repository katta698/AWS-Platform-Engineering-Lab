output "bucket_name" {
  description = "Name of the CloudTrail log bucket."
  value       = aws_s3_bucket.trail.id
}

output "bucket_arn" {
  description = "ARN of the CloudTrail log bucket."
  value       = aws_s3_bucket.trail.arn
}

output "trail_arn" {
  description = "ARN of the organization trail."
  value       = aws_cloudtrail.org.arn
}

output "trail_name" {
  description = "Name of the organization trail."
  value       = aws_cloudtrail.org.name
}

output "organization_id" {
  description = <<-EOT
    The AWS Organizations ID.

    Surfaced because it is the first path segment an organization trail writes
    under, so the Athena table's location and projection template are both built
    from it. A single-account trail has no equivalent segment, which is why the
    org-trail table needs a different shape from the one AWS documents.
  EOT
  value       = data.aws_organizations_organization.current.id
}

output "s3_prefix" {
  description = "Prefix organization trail objects are delivered under, up to where partitioning begins."
  value       = "AWSLogs/${data.aws_organizations_organization.current.id}"
}
