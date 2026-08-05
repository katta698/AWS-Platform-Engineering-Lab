###############################################################################
# WAF module -- one web ACL, its rules, and its logging pipeline.
#
# Instantiated twice by the dev environment: once at CLOUDFRONT scope (edge)
# and once at REGIONAL scope (origin). Everything in here is scope-agnostic
# except where noted; the caller supplies the correctly-regioned provider,
# because a CLOUDFRONT-scope web ACL and its log group must both live in
# us-east-1 while a REGIONAL one must live in the region of the resource it
# protects.
#
# Rule order is deliberate. WAF evaluates rules by ascending priority and
# stops at the first terminating action, so the cheapest and most definitive
# checks run first:
#
#   10  blocked IP set   -- break-glass deny, 1 WCU, no inspection needed
#   20  rate limit       -- volumetric abuse of otherwise-legitimate requests
#   30  CommonRuleSet    -- OWASP-class signatures, 700 WCU
#   40  KnownBadInputs   -- active-CVE exploitation, 200 WCU
#   50  Anti-DDoS        -- adaptive L7 DDoS with browser challenges, 50 WCU
#
# Total ~953 WCU against the 1500 included in the base price, so this web ACL
# incurs no WCU overage charge.
###############################################################################

locals {
  # Custom rules take an `action` block; managed rule groups take an
  # `override_action` block. Count mode is expressed differently for each,
  # which is a genuinely easy thing to get wrong -- setting override_action
  # to `none` does NOT mean "no action", it means "use the rule group's own
  # configured actions", i.e. enforce.
  custom_rule_action   = var.count_mode ? "count" : "block"
  managed_group_action = var.count_mode ? "count" : "none"

  log_group_name = "aws-waf-logs-${var.name_prefix}"
}

###############################################################################
# Break-glass IP deny list
###############################################################################

resource "aws_wafv2_ip_set" "blocked" {
  name               = "${var.name_prefix}-blocked-ips"
  description        = "Break-glass deny list. Empty until an operator adds an address during an incident."
  scope              = var.scope
  ip_address_version = "IPV4"
  addresses          = var.blocked_ip_cidrs

  tags = var.tags
}

###############################################################################
# Web ACL
###############################################################################

resource "aws_wafv2_web_acl" "this" {
  name        = var.name_prefix
  description = "Week 13 ${var.scope} web ACL -- managed rules, rate limiting, and adaptive L7 DDoS protection."
  scope       = var.scope

  # Allow by default. A WAF fronting a real application blocks by exception;
  # a default-block posture would require enumerating every legitimate request
  # shape up front, which is not achievable for a general web application.
  default_action {
    allow {}
  }

  ############################################################################
  # 10 -- Break-glass IP deny
  ############################################################################
  rule {
    name     = "blocked-ip-set"
    priority = 10

    action {
      dynamic "block" {
        for_each = local.custom_rule_action == "block" ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = local.custom_rule_action == "count" ? [1] : []
        content {}
      }
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.blocked.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-blocked-ip-set"
      sampled_requests_enabled   = true
    }
  }

  ############################################################################
  # 20 -- Rate limiting
  #
  # evaluation_window_sec of 60 rather than the 300 default: WAF re-checks the
  # rate roughly every 10 seconds regardless, but a 5-minute lookback means an
  # attacker's burst is averaged across five minutes before it crosses the
  # threshold. A 60-second window reacts to a burst as a burst.
  #
  # aggregate_key_type IP is correct for this demo but wrong for a real app
  # whose users sit behind a shared corporate NAT -- every user in the office
  # would share one aggregation bucket and be throttled together. CUSTOM_KEYS
  # over a session identifier is the fix in that case.
  ############################################################################
  rule {
    name     = "rate-limit-per-ip"
    priority = 20

    action {
      dynamic "block" {
        for_each = local.custom_rule_action == "block" ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = local.custom_rule_action == "count" ? [1] : []
        content {}
      }
    }

    statement {
      rate_based_statement {
        limit                 = var.rate_limit
        aggregate_key_type    = "IP"
        evaluation_window_sec = var.rate_evaluation_window_sec
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  ############################################################################
  # 30 -- AWS Managed Rules: Core rule set (700 WCU)
  #
  # The broadest-value group: OWASP Top 10 signatures covering XSS, LFI/RFI,
  # SSRF-to-EC2-metadata, and request size restrictions. The size rules are
  # the usual source of false positives -- SizeRestrictions_BODY blocks bodies
  # over 8KB, which a legitimate file upload will trip. Add a
  # rule_action_override for that specific rule rather than dropping the group.
  ############################################################################
  rule {
    name     = "aws-common-rule-set"
    priority = 30

    override_action {
      dynamic "none" {
        for_each = local.managed_group_action == "none" ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = local.managed_group_action == "count" ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  ############################################################################
  # 40 -- AWS Managed Rules: Known bad inputs (200 WCU)
  #
  # Active-CVE exploitation patterns: Log4Shell, Java deserialization RCE,
  # exploitable paths. AWS updates this group as new CVEs land, which is the
  # entire argument for a managed group over hand-written regex -- a
  # self-maintained equivalent goes stale within weeks.
  ############################################################################
  rule {
    name     = "aws-known-bad-inputs"
    priority = 40

    override_action {
      dynamic "none" {
        for_each = local.managed_group_action == "none" ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = local.managed_group_action == "count" ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  ############################################################################
  # 50 -- AWS Managed Rules: Anti-DDoS (50 WCU)
  #
  # Adaptive application-layer DDoS protection. Profiles normal traffic and
  # reacts within seconds, applying silent browser challenges to requests
  # labelled as DDoS-suspected. This is the rule group that replaces AWS
  # Shield Advanced's automatic application-layer mitigation, which AWS is
  # sunsetting on 2027-01-01 -- and unlike Shield Advanced ($3,000/month) it
  # costs the standard $1/month per rule group.
  #
  # The challenge is silent: a real browser solves it transparently. A scripted
  # client cannot, which is the point -- but it also means genuine non-browser
  # callers need an exemption, hence exempt_uri_regular_expression.
  ############################################################################
  rule {
    name     = "aws-anti-ddos"
    priority = 50

    override_action {
      dynamic "none" {
        for_each = local.managed_group_action == "none" ? [1] : []
        content {}
      }
      dynamic "count" {
        for_each = local.managed_group_action == "count" ? [1] : []
        content {}
      }
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesAntiDDoSRuleSet"

        managed_rule_group_configs {
          aws_managed_rules_anti_ddos_rule_set {
            sensitivity_to_block = var.anti_ddos_sensitivity_to_block

            client_side_action_config {
              challenge {
                usage_of_action = "ENABLED"
                sensitivity     = "HIGH"

                dynamic "exempt_uri_regular_expression" {
                  for_each = var.anti_ddos_challenge_exempt_uri_regexes
                  content {
                    regex_string = exempt_uri_regular_expression.value
                  }
                }
              }
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name_prefix}-anti-ddos"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name_prefix}-web-acl"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

###############################################################################
# Logging
#
# The log group name MUST start with "aws-waf-logs-" -- AWS rejects the
# logging configuration otherwise, and the error does not make the reason
# obvious. It must also live in the same region and account as the web ACL.
###############################################################################

resource "aws_cloudwatch_log_group" "waf" {
  name              = local.log_group_name
  retention_in_days = var.log_retention_days

  tags = var.tags
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# WAF would otherwise create and update a single shared account-wide log
# resource policy named AWSWAF-LOGS. With enough web ACLs in an account that
# policy can exceed the maximum policy size and the logging configuration then
# fails to create. Managing a narrowly-scoped policy per web ACL avoids
# contributing to that shared policy at all.
data "aws_iam_policy_document" "waf_logs" {
  version = "2012-10-17"

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.waf.arn}:*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "waf_logs" {
  policy_name     = "${var.name_prefix}-waf-logs"
  policy_document = data.aws_iam_policy_document.waf_logs.json
}

resource "aws_wafv2_web_acl_logging_configuration" "this" {
  resource_arn            = aws_wafv2_web_acl.this.arn
  log_destination_configs = [aws_cloudwatch_log_group.waf.arn]

  # A WAF log records the request that was inspected -- which means it records
  # credentials unless told not to. Redaction here is what stops the security
  # control from becoming the disclosure vector.
  redacted_fields {
    single_header {
      name = "authorization"
    }
  }

  redacted_fields {
    single_header {
      name = "cookie"
    }
  }

  redacted_fields {
    single_header {
      name = "x-api-key"
    }
  }

  depends_on = [aws_cloudwatch_log_resource_policy.waf_logs]
}
