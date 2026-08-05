variable "name_prefix" {
  description = "Prefix for every resource this module creates. Must be unique per web ACL, because both instantiations of this module can land in the same region (us-east-1) and would otherwise collide on log group names."
  type        = string
}

variable "scope" {
  description = "WAF scope. CLOUDFRONT for a CloudFront distribution (the web ACL and its log group must then live in us-east-1); REGIONAL for API Gateway, ALB, AppSync, etc."
  type        = string

  validation {
    condition     = contains(["CLOUDFRONT", "REGIONAL"], var.scope)
    error_message = "scope must be either CLOUDFRONT or REGIONAL."
  }
}

variable "count_mode" {
  description = <<-EOT
    When true, every rule is deployed in Count mode: matches are recorded in
    metrics and logs but nothing is blocked. This is the first half of a
    two-phase rollout -- deploy in Count, observe what would have been blocked
    (including legitimate traffic caught by false positives), then flip to
    false to enforce. Blocking on day one is how WAF rollouts break production
    and get switched off entirely.
  EOT
  type        = bool
  default     = true
}

variable "rate_limit" {
  description = "Requests from a single IP within the evaluation window before the rate-based rule triggers. AWS enforces a minimum of 10."
  type        = number
  default     = 100

  validation {
    condition     = var.rate_limit >= 10
    error_message = "AWS WAF requires a rate-based rule limit of at least 10."
  }
}

variable "rate_evaluation_window_sec" {
  description = "Lookback window for the rate-based rule. Only 60, 120, 300, and 600 are valid; the AWS default is 300. 60 is used here so the rule reacts within a minute rather than five."
  type        = number
  default     = 60

  validation {
    condition     = contains([60, 120, 300, 600], var.rate_evaluation_window_sec)
    error_message = "evaluation_window_sec must be one of 60, 120, 300, 600."
  }
}

variable "blocked_ip_cidrs" {
  description = "Break-glass deny list. CIDR notation; a single address is /32. Empty by default -- populated when you need a specific attacker gone immediately rather than waiting for a managed rule to catch up."
  type        = list(string)
  default     = []
}

variable "anti_ddos_sensitivity_to_block" {
  description = "How readily the Anti-DDoS rule group's DDoSRequests rule blocks based on DDoS suspicion labelling. LOW (AWS default), MEDIUM, or HIGH."
  type        = string
  default     = "LOW"

  validation {
    condition     = contains(["LOW", "MEDIUM", "HIGH"], var.anti_ddos_sensitivity_to_block)
    error_message = "anti_ddos_sensitivity_to_block must be LOW, MEDIUM, or HIGH."
  }
}

variable "anti_ddos_challenge_exempt_uri_regexes" {
  description = <<-EOT
    URI patterns that cannot handle a silent browser challenge -- machine-to-machine
    endpoints, webhooks, health checks. A non-browser client cannot execute the
    JavaScript challenge, so without an exemption a DDoS event would fail those
    callers outright rather than protecting them.

    MUST be non-empty. AWS rejects CreateWebACL with WAFInvalidParameterException
    when the Anti-DDoS challenge action is ENABLED and this list is empty, even
    though the Terraform provider documents the field as optional. Confirmed by a
    real apply failure on 2026-08-05 -- terraform validate and plan both pass.
  EOT
  type        = list(string)
  default     = ["^/health$"]

  validation {
    condition     = length(var.anti_ddos_challenge_exempt_uri_regexes) > 0
    error_message = "At least one exempt URI regex is required: AWS rejects the web ACL if the Anti-DDoS challenge action is ENABLED with an empty exemption list."
  }
}

variable "log_retention_days" {
  description = "Retention for the WAF log group. Short by default -- WAF logs one record per inspected request and will accumulate cost otherwise."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags applied to taggable resources in this module."
  type        = map(string)
  default     = {}
}
