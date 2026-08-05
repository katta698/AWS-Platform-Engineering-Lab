output "web_acl_arn" {
  description = "ARN of the web ACL. Needed to associate it with a protected resource, and (for CLOUDFRONT scope) to set web_acl_id on the distribution."
  value       = aws_wafv2_web_acl.this.arn
}

output "web_acl_id" {
  description = "ID of the web ACL."
  value       = aws_wafv2_web_acl.this.id
}

output "web_acl_name" {
  description = "Name of the web ACL, used as the CloudWatch metric dimension when querying WAF metrics."
  value       = aws_wafv2_web_acl.this.name
}

output "web_acl_capacity" {
  description = "WCUs consumed by this web ACL. Compare against the 1500 included in the base price -- anything above incurs a per-request overage charge."
  value       = aws_wafv2_web_acl.this.capacity
}

output "log_group_name" {
  description = "CloudWatch log group receiving this web ACL's request logs."
  value       = aws_cloudwatch_log_group.waf.name
}

output "blocked_ip_set_arn" {
  description = "ARN of the break-glass IP deny list."
  value       = aws_wafv2_ip_set.blocked.arn
}
