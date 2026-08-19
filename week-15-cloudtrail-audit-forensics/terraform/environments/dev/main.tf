###############################################################################
# Week 15: CloudTrail Organization Trail + Audit Forensics
#
# Weeks 11 and 12 answer "is something wrong?" -- Security Hub and GuardDuty find
# the open security group and close it; Config reports whether a resource is
# compliant. Both describe STATE.
#
# This week answers "WHO DID IT, when, from where, and what else did they touch?"
# CloudTrail records ACTIONS, and once an auto-remediation has fixed the problem,
# the action record is the only evidence left that it ever happened.
#
#   Organization trail (management events only -- the free copy)
#         |
#         v
#   S3 bucket  --(5-key partition projection, no crawler)-->  Glue table
#         |                                                        |
#         |                                                Athena workgroup
#         |                                              (10 GB scan ceiling)
#         v                                                /            \
#   lifecycle expiry                            7 saved queries     audit_analyzer
#   (365 days -- must exceed                    (forensics, human)   (daily, metrics)
#    the console's own 90)                                                 |
#                                                                CloudWatch alarms
#                                                              (ALL static: these
#                                                               should be zero)
#                                                                          |
#                                                                         SNS
#
# The motivating incident is real and from this lab: during Week 12 the account's
# AWS Config recorder was deleted mid-build by an unrelated project's cleanup
# script. The build broke, the recorder was rebuilt -- and "who deleted it" was
# never answerable by anyone.
#
# On the original roadmap topic: this was planned as "CloudTrail Lake + Audit
# Automation". CloudTrail Lake closed to new customers on 2026-05-31 and this
# account has no event data store, so that build is impossible. AWS's own
# org-wide Athena page still recommends Lake for exactly this case -- advice that
# no longer works for anyone starting today.
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
      name = "week-15-dev"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}

# The organization. Supplies both the org ID (the first path segment an org trail
# writes under) and the live account list.
data "aws_organizations_organization" "current" {}

# Enabled regions only. Not a hardcoded list, because the region projection has
# to cover everywhere the multi-region trail could write -- and "which regions
# are enabled" is a fact about the account, not a constant.
data "aws_regions" "enabled" {}

locals {
  name_prefix = "week15-audit"

  common_tags = {
    Project     = "AWS-Platform-Engineering-Lab"
    Week        = "15"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  #############################################################################
  # Accounts to project as partitions.
  #
  # Derived from live organization state, filtered to ACTIVE. This matters more
  # than it looks:
  #
  #   * Partition projection needs a FINITE set for a non-date key, so accounts
  #     are an enum. An account missing from that enum has its events sitting in
  #     S3, perfectly intact, and invisible to every query -- silently.
  #   * Deriving the list here means the code self-corrects on the next apply
  #     rather than drifting until somebody notices. It does NOT make the table
  #     self-updating: adding an account still requires an apply. That is the
  #     honest trade-off of projection over a crawler, and it belongs in the
  #     write-up rather than being smoothed over.
  #   * SUSPENDED accounts are excluded deliberately (Jay's call). They generate
  #     no API activity, so excluding them costs nothing in coverage and keeps
  #     the projected partition space small. This org has 8 of them.
  #
  # The trail itself is org-wide regardless -- only the TABLE is scoped.
  #############################################################################
  active_account_ids = sort([
    for a in data.aws_organizations_organization.current.accounts : a.id
    if a.status == "ACTIVE"
  ])

  bucket_name     = "${local.name_prefix}-${data.aws_caller_identity.current.account_id}-${var.aws_region}"
  database_name   = replace("${local.name_prefix}_db", "-", "_")
  table_name      = "cloudtrail_events"
  qualified_table = "\"${local.database_name}\".\"${local.table_name}\""

  # Saved queries, rendered from the .sql files so the SQL stays reviewable as
  # SQL rather than buried in HCL strings.
  named_queries = {
    partition-sanity-check = {
      description = "RUN THIS FIRST. Confirms partition projection resolves against the org-trail layout. Zero rows here means every other query is silently returning nothing."
      sql         = templatefile("${path.module}/../../../athena/01_partition_sanity_check.sql", { table = local.qualified_table })
    }
    who-changed-this-resource = {
      description = "Who deleted or modified a named resource, when, from where. Edit the resource placeholder before running."
      sql         = templatefile("${path.module}/../../../athena/02_who_changed_this_resource.sql", { table = local.qualified_table })
    }
    principal-activity-timeline = {
      description = "Everything one user or role did in a window. Handles role sessions, where the useful name is on sessionissuer rather than the top level."
      sql         = templatefile("${path.module}/../../../athena/03_principal_activity_timeline.sql", { table = local.qualified_table })
    }
    changes-outside-terraform = {
      description = "Mutating changes that did not come from Terraform. Filters on user agent, not principal -- the same role used via console and via Terraform is identical by principal."
      sql         = templatefile("${path.module}/../../../athena/04_changes_outside_terraform.sql", { table = local.qualified_table })
    }
    root-account-usage = {
      description = "Root account actions. Should be zero, and is alarmed on a static threshold for that reason."
      sql         = templatefile("${path.module}/../../../athena/05_root_account_usage.sql", { table = local.qualified_table })
    }
    console-login-without-mfa = {
      description = "Successful console sign-ins with no second factor. Note mfaauthenticated is a STRING and can be NULL for federated sign-ins."
      sql         = templatefile("${path.module}/../../../athena/06_console_login_without_mfa.sql", { table = local.qualified_table })
    }
    activity-in-unexpected-regions = {
      description = "Mutating activity outside the regions this estate uses. Only answerable because the trail is multi-region and the region enum covers all enabled regions."
      sql         = templatefile("${path.module}/../../../athena/07_activity_in_unexpected_regions.sql", { table = local.qualified_table })
    }
  }
}

###############################################################################
# Capture
###############################################################################

module "audit_trail" {
  source = "../../modules/audit_trail"

  name_prefix                = local.name_prefix
  bucket_name                = local.bucket_name
  home_region                = var.aws_region
  is_organization_trail      = var.is_organization_trail
  is_multi_region_trail      = var.is_multi_region_trail
  log_retention_days         = var.log_retention_days
  enable_log_file_validation = var.enable_log_file_validation
}

###############################################################################
# Query layer
###############################################################################

module "analytics" {
  source = "../../modules/analytics"

  name_prefix     = local.name_prefix
  database_name   = local.database_name
  table_name      = local.table_name
  bucket_name     = module.audit_trail.bucket_name
  bucket_arn      = module.audit_trail.bucket_arn
  organization_id = module.audit_trail.organization_id

  account_ids = local.active_account_ids
  regions     = data.aws_regions.enabled.names

  projection_start_year   = var.projection_start_year
  projection_end_year     = var.projection_end_year
  bytes_scanned_cutoff_gb = var.bytes_scanned_cutoff_gb
  named_queries           = local.named_queries
}

###############################################################################
# Analysis and alerting
###############################################################################

module "monitoring" {
  source = "../../modules/monitoring"

  name_prefix       = local.name_prefix
  alert_email       = var.alert_email
  lambda_source_dir = "${path.module}/../../../lambda/audit_analyzer"
  lambda_build_dir  = "${path.module}/../../../lambda/builds"

  athena_database    = module.analytics.database_name
  athena_table       = module.analytics.table_name
  athena_workgroup   = module.analytics.workgroup_name
  results_bucket_arn = module.audit_trail.bucket_arn

  expected_regions       = var.expected_regions
  schedule_expression    = var.schedule_expression
  lambda_timeout_seconds = var.lambda_timeout_seconds
}
