###############################################################################
# Week 12: AWS Config Compliance Automation
#
# Three Config rules -- deliberately distinct from the ~300 securityhub-*
# rules Security Hub (Week 11) already created in this account -- check
# governance/durability compliance Security Hub has no concept of: mandatory
# tagging, S3 versioning, S3 default encryption. The two S3 rules auto-remediate
# (tag-scoped opt-in, via AWS-managed SSM Automation documents) through a single
# conformance pack -- the pack's own console compliance view is the "dashboard".
# required-tags is notify-only: a missing tag value can't be safely invented. A
# scheduled Lambda summarizes compliance for just these 3 rules into a daily
# SNS digest.
###############################################################################

terraform {
  required_version = ">= 1.10"
  required_providers {
    # Same 6.x line as Week 11 -- aws_config_conformance_pack and
    # aws_config_remediation_configuration are both stable there.
    aws = { source = "hashicorp/aws", version = "~> 6.0" }
  }

  cloud {
    organization = "Katta"
    workspaces {
      name = "week-12-dev"
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
    Week      = "12"
    Component = "config-compliance-automation"
    ManagedBy = "terraform"
  }
}

# Config rules + remediation + conformance pack. Reuses the account's existing
# Config recorder (telemetry-dashboard-recorder, confirmed live before this
# week was scaffolded) -- this module creates no recorder of its own.
module "config_compliance" {
  source                = "../../modules/config_compliance"
  name_prefix           = var.name_prefix
  remediation_tag_key   = var.remediation_tag_key
  remediation_tag_value = var.remediation_tag_value
  required_tag_keys     = var.required_tag_keys
  tags                  = local.common_tags
}

# Daily compliance digest, scoped only to this week's 3 rules -- not the 300
# securityhub-* ones already in the account.
module "reporter" {
  source             = "../../modules/reporter"
  name_prefix        = var.name_prefix
  alert_email        = var.alert_email
  config_rule_names  = values(module.config_compliance.config_rule_names)
  log_retention_days = var.log_retention_days
  tags               = local.common_tags
}
