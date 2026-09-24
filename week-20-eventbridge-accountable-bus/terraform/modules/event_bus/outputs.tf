output "bus_name" {
  value = aws_cloudwatch_event_bus.this.name
}

output "bus_arn" {
  value = aws_cloudwatch_event_bus.this.arn
}

output "archive_name" {
  description = "Replay source. Note a replay targets the rules that exist NOW."
  value       = aws_cloudwatch_event_archive.this.name
}

output "discoverer_id" {
  value = aws_schemas_discoverer.this.id
}

output "trail_name" {
  description = "Scoped to PutEvents on this bus only -- an unscoped selector bills for the whole account"
  value       = aws_cloudtrail.bus.name
}

output "trail_bucket" {
  value = aws_s3_bucket.trail.id
}
