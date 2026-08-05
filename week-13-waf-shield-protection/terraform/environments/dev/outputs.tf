output "cloudfront_url" {
  description = "Public edge URL -- the path a normal user takes, protected by the CLOUDFRONT-scope web ACL and Shield Standard."
  value       = module.protected_app.cloudfront_url
}

output "api_invoke_url" {
  description = "Direct-to-origin URL that bypasses CloudFront. Still inspected, by the REGIONAL web ACL -- that is the point of having both."
  value       = module.protected_app.api_invoke_url
}

output "edge_web_acl_name" {
  description = "Name of the CLOUDFRONT-scope web ACL."
  value       = module.waf_edge.web_acl_name
}

output "regional_web_acl_name" {
  description = "Name of the REGIONAL-scope web ACL."
  value       = module.waf_regional.web_acl_name
}

output "web_acl_capacity" {
  description = "WCUs consumed by each web ACL. Both should sit well under the 1500 included in the base price -- anything above adds a per-request overage charge."
  value = {
    edge     = module.waf_edge.web_acl_capacity
    regional = module.waf_regional.web_acl_capacity
  }
}

output "waf_log_groups" {
  description = "CloudWatch log groups receiving WAF request logs."
  value = {
    edge     = module.waf_edge.log_group_name
    regional = module.waf_regional.log_group_name
  }
}

output "lambda_log_group" {
  description = "Echo function log group -- shows which requests actually reached the origin."
  value       = module.protected_app.lambda_log_group_name
}

output "count_mode_active" {
  description = "True while rules are observing rather than enforcing. Requests are NOT being blocked while this is true."
  value       = var.count_mode
}

output "sns_topic_arns" {
  description = "Alarm notification topics, one per region."
  value = {
    edge     = module.monitoring_edge.sns_topic_arn
    regional = module.monitoring_regional.sns_topic_arn
  }
}
