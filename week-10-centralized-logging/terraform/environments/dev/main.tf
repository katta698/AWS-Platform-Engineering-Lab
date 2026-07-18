###############################################################################
# Week 10: Centralised Logging Platform
# OAM sink/link share logs + metrics across accounts for query-in-place;
# an org-wide CloudWatch centralization rule physically copies matching log
# groups into this (management) account; metric filter -> alarm -> SNS email
# alerts on the centralized error stream; a scheduled log-generator Lambda in
# the source account provides live multi-account traffic to prove it all.
###############################################################################

terraform {
  required_version = ">= 1.10"
  required_providers {
    # aws_observabilityadmin_centralization_rule_for_organization exists only
    # since provider 6.21.0 (log selection args reworked in 6.39.0) — this
    # week cannot use the 5.x pin earlier weeks carry.
    aws = { source = "hashicorp/aws", version = "~> 6.39" }
  }

  cloud {
    organization = "Katta"
    workspaces {
      name = "week-10-dev"
    }
  }
}

# Monitoring / destination account (org management account).
provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

# Source (spoke) account — the member account that produces logs.
provider "aws" {
  alias  = "source"
  region = var.aws_region
  assume_role {
    role_arn = "arn:aws:iam::${var.source_account_id}:role/${var.source_role_name}"
  }
  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}
data "aws_organizations_organization" "current" {}

locals {
  common_tags = {
    Project   = var.project
    Week      = "10"
    ManagedBy = "terraform"
  }
  # The generator writes here in the source account; the centralization rule
  # copies a log group with the identical name into this account.
  app_log_group_name = "${var.log_group_base}/log-generator"
}

# Attachment point + trust boundary in the monitoring account.
module "oam_hub" {
  source          = "../../modules/oam_hub"
  name            = "${var.project}-sink"
  organization_id = data.aws_organizations_organization.current.id
}

# Source account opts in to sharing logs + metrics with the sink.
module "oam_spoke" {
  source = "../../modules/oam_spoke"
  providers = {
    aws = aws.source
  }
  sink_arn = module.oam_hub.sink_arn
}

# Scheduled Lambda in the source account emitting structured multi-level logs.
module "log_generator" {
  source = "../../modules/log_generator"
  providers = {
    aws = aws.source
  }
  function_name  = "${var.project}-log-generator"
  log_group_name = local.app_log_group_name
}

# Org-wide rule copying matching log groups into this account (first copy is
# free of ingestion charges; only processes log data written after creation).
module "log_centralization" {
  source                 = "../../modules/log_centralization"
  rule_name              = "${var.project}-rule"
  organization_id        = data.aws_organizations_organization.current.id
  source_region          = var.aws_region
  destination_account_id = data.aws_caller_identity.current.account_id
  destination_region     = var.aws_region
  log_group_prefix       = var.log_group_base
}

# Metric filter -> alarm -> SNS email on the centralized copy, plus the
# cross-account dashboard.
module "alerting" {
  source                     = "../../modules/alerting"
  project                    = var.project
  centralized_log_group_name = local.app_log_group_name
  alert_email                = var.alert_email
  source_account_id          = var.source_account_id
  generator_function_name    = "${var.project}-log-generator"
  aws_region                 = var.aws_region

  depends_on = [module.log_centralization]
}
