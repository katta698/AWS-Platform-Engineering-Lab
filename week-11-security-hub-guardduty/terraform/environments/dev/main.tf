###############################################################################
# Week 11: Security Hub + GuardDuty Auto-Remediation
#
# Security Hub CSPM (FSBP standard) + GuardDuty foundational detection feed
# findings into EventBridge. Two tag-gated Lambdas auto-remediate clear-cut
# misconfigurations (world-open management ports, public S3 buckets) and write
# the result back to the finding; a third Lambda escalates GuardDuty threat
# findings to SNS for human triage. Failed remediations land in a DLQ that
# alarms. A Security Hub automation rule escalates production-tagged failures
# to CRITICAL before anything is routed.
###############################################################################

terraform {
  required_version = ">= 1.10"
  required_providers {
    # Classic Security Hub CSPM + GuardDuty + aws_securityhub_automation_rule
    # are all stable in the 6.x line. Unlike Week 10 there is no need for a
    # specific minor floor — the unified Security Hub v2 (which would need a
    # newer, still-unreleased resource) is deliberately not used here.
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }

  cloud {
    organization = "Katta"
    workspaces {
      name = "week-11-dev"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project   = "AWS-Platform-Engineering-Lab"
    Week      = "11"
    Component = "security-hub-guardduty-remediation"
    ManagedBy = "terraform"
  }
}

# Security Hub CSPM: enable, subscribe FSBP, aggregate findings, escalate prod.
module "securityhub" {
  source               = "../../modules/securityhub"
  name_prefix          = var.name_prefix
  production_tag_key   = var.production_tag_key
  production_tag_value = var.production_tag_value
}

# GuardDuty: foundational threat detection (Extended Threat Detection free).
module "guardduty" {
  source                       = "../../modules/guardduty"
  finding_publishing_frequency = var.finding_publishing_frequency
  tags                         = local.common_tags
}

# Remediation backbone: EventBridge rules, Lambdas, SNS, DLQ, alarm.
module "remediation" {
  source                 = "../../modules/remediation"
  name_prefix            = var.name_prefix
  alert_email            = var.alert_email
  remediation_tag_key    = var.remediation_tag_key
  remediation_tag_value  = var.remediation_tag_value
  high_risk_ports        = var.high_risk_ports
  guardduty_min_severity = var.guardduty_min_severity
  log_retention_days     = var.log_retention_days
  tags                   = local.common_tags

  # Findings can only flow once Security Hub and GuardDuty are enabled — make
  # the whole pipeline come up in a sensible order.
  depends_on = [module.securityhub, module.guardduty]
}
