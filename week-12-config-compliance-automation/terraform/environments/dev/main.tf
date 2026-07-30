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
#
# This week also provisions its own Config recorder (module.config_recorder) --
# the account's previous recorder belonged to an unrelated project and was
# deleted as part of that project's own cleanup on 2026-07-29 (confirmed via
# CloudTrail, not this project's doing). This Lab now owns its recorder going
# forward, which incidentally also restores Week 11's Security Hub FSBP
# dependency -- no changes needed in Week 11's own Terraform.
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

# This Lab's own Config recorder -- see the header note above for why this
# exists now (it didn't when this week was first scaffolded).
module "config_recorder" {
  source      = "../../modules/config_recorder"
  name_prefix = var.name_prefix
  tags        = local.common_tags
}

# Config rules + remediation + conformance pack.
module "config_compliance" {
  source                = "../../modules/config_compliance"
  name_prefix           = var.name_prefix
  remediation_tag_key   = var.remediation_tag_key
  remediation_tag_value = var.remediation_tag_value
  required_tag_keys     = var.required_tag_keys
  tags                  = local.common_tags

  # Rules can't evaluate anything without an active recorder.
  depends_on = [module.config_recorder]
}

# Daily compliance digest, scoped only to this week's 3 rules -- not the 300
# securityhub-* ones already in the account.
module "reporter" {
  source                = "../../modules/reporter"
  name_prefix           = var.name_prefix
  alert_email           = var.alert_email
  conformance_pack_name = module.config_compliance.conformance_pack_name
  log_retention_days    = var.log_retention_days
  tags                  = local.common_tags
}
