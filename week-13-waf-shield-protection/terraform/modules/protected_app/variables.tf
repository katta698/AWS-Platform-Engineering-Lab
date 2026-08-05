variable "name_prefix" {
  description = "Prefix for every resource this module creates."
  type        = string
}

variable "lambda_source_dir" {
  description = "Directory containing handler.py for the echo origin."
  type        = string
}

variable "stage_name" {
  description = "API Gateway stage name. Also becomes the CloudFront origin path, since a REST API serves its stage as the first path segment."
  type        = string
  default     = "prod"
}

variable "log_retention_days" {
  description = "Retention for the Lambda log group."
  type        = number
  default     = 7
}

variable "cloudfront_web_acl_arn" {
  description = <<-EOT
    ARN of a CLOUDFRONT-scope web ACL to attach to the distribution. Note the
    asymmetry with the regional side: CloudFront takes the web ACL as an
    attribute on the distribution itself, whereas API Gateway, ALB, and other
    regional resources are attached via a separate
    aws_wafv2_web_acl_association resource.
  EOT
  type        = string
}

variable "tags" {
  description = "Tags applied to taggable resources in this module."
  type        = map(string)
  default     = {}
}
