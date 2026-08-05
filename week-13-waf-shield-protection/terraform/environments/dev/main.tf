###############################################################################
# Week 13: AWS WAF + Shield Standard
#
# Defence in depth across two WAF scopes:
#
#   CloudFront distribution  <- CLOUDFRONT-scope web ACL   (edge)
#            |
#            v
#   API Gateway REST API     <- REGIONAL-scope web ACL     (origin)
#            |
#            v
#   Lambda echo function
#
# Why two web ACLs rather than one: a single edge ACL protects only the
# requests that actually go through CloudFront. The API Gateway invoke URL
# remains publicly reachable, so anyone who discovers it can bypass the edge
# entirely. The regional ACL is what makes that bypass pointless.
#
# On Shield Standard: there is nothing to provision. It is already active on
# every AWS account at no charge, protecting CloudFront and other edge
# resources against L3/L4 volumetric attacks. It has no Terraform resource
# and no console toggle. The reason CloudFront is in this design at all is
# that Shield Standard's protection applies there -- but the entire L7 layer,
# where HTTP floods and exploit traffic live, is WAF's job and is what this
# code actually builds.
###############################################################################

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "week-13-dev"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

# A CLOUDFRONT-scope web ACL must be created in us-east-1, and its log group
# and CloudWatch metrics live there too. This alias exists solely for that.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.common_tags
  }
}

locals {
  project = "week13-waf"

  common_tags = {
    Project     = "AWS-Platform-Engineering-Lab"
    Week        = "13"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

###############################################################################
# Edge WAF (CLOUDFRONT scope, us-east-1)
###############################################################################

module "waf_edge" {
  source = "../../modules/waf"

  providers = {
    aws = aws.us_east_1
  }

  name_prefix = "${local.project}-edge"
  scope       = "CLOUDFRONT"

  count_mode                 = var.count_mode
  rate_limit                 = var.rate_limit
  rate_evaluation_window_sec = var.rate_evaluation_window_sec
  blocked_ip_cidrs           = var.blocked_ip_cidrs
  log_retention_days         = var.log_retention_days

  anti_ddos_challenge_exempt_uri_regexes = var.anti_ddos_challenge_exempt_uri_regexes

  tags = local.common_tags
}

###############################################################################
# Origin WAF (REGIONAL scope)
###############################################################################

module "waf_regional" {
  source = "../../modules/waf"

  name_prefix = "${local.project}-regional"
  scope       = "REGIONAL"

  count_mode                 = var.count_mode
  rate_limit                 = var.rate_limit
  rate_evaluation_window_sec = var.rate_evaluation_window_sec
  blocked_ip_cidrs           = var.blocked_ip_cidrs
  log_retention_days         = var.log_retention_days

  anti_ddos_challenge_exempt_uri_regexes = var.anti_ddos_challenge_exempt_uri_regexes

  tags = local.common_tags
}

###############################################################################
# The protected application
###############################################################################

module "protected_app" {
  source = "../../modules/protected_app"

  name_prefix        = local.project
  lambda_source_dir  = "${path.module}/../../../lambda/echo_api"
  stage_name         = var.stage_name
  log_retention_days = var.log_retention_days

  cloudfront_web_acl_arn = module.waf_edge.web_acl_arn

  tags = local.common_tags
}

# CloudFront takes its web ACL as a distribution attribute; every regional
# resource type needs this separate association resource instead. Forgetting
# it is a silent failure -- the web ACL exists, reports healthy, and inspects
# nothing at all.
resource "aws_wafv2_web_acl_association" "api_stage" {
  resource_arn = module.protected_app.api_stage_arn
  web_acl_arn  = module.waf_regional.web_acl_arn
}

###############################################################################
# Monitoring
#
# Two instantiations because a CloudWatch alarm can only notify an SNS topic
# in its own region, and the two web ACLs publish metrics in different regions.
# This does mean two subscription-confirmation emails on first apply.
###############################################################################

module "monitoring_edge" {
  source = "../../modules/monitoring"

  providers = {
    aws = aws.us_east_1
  }

  name_prefix  = "${local.project}-edge"
  web_acl_name = module.waf_edge.web_acl_name

  # null, not "Global": CloudFront-scope metrics carry no Region dimension at
  # all. Verified live against `aws cloudwatch list-metrics` -- a "Global"
  # value matches nothing and leaves the alarm permanently INSUFFICIENT_DATA.
  metric_region_dimension = null

  alert_email                = var.alert_email
  blocked_requests_threshold = var.blocked_requests_threshold
  counted_requests_threshold = var.counted_requests_threshold

  tags = local.common_tags
}

module "monitoring_regional" {
  source = "../../modules/monitoring"

  name_prefix             = "${local.project}-regional"
  web_acl_name            = module.waf_regional.web_acl_name
  metric_region_dimension = var.aws_region

  alert_email                = var.alert_email
  blocked_requests_threshold = var.blocked_requests_threshold
  counted_requests_threshold = var.counted_requests_threshold

  tags = local.common_tags
}
