###############################################################################
# Week 05 — Cost Anomaly Detection
# Environment : dev
# Backend     : HCP Terraform (VCS-driven)
#               Org = Katta | Workspace = week-05-dev
#
# Architecture:
#   Cost Explorer → Cost Anomaly Monitor → SNS (raw)
#                                               ↓
#                                          Lambda (format)
#                                               ↓
#                                          SNS (alert) → Email
###############################################################################

terraform {
  cloud {
    organization = "Katta"
    workspaces {
      name = "week-05-dev"
    }
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  required_version = ">= 1.6.0"
}

provider "aws" {
  region = var.aws_region
}

locals {
  tags = {
    Project     = var.project
    Environment = var.environment
    Week        = "05"
    ManagedBy   = "terraform"
  }
}

# ── SNS Topics ────────────────────────────────────────────────────────────────
module "sns" {
  source      = "../../modules/sns"
  project     = var.project
  environment = var.environment
  alert_email = var.alert_email
  tags        = local.tags
}

# ── Lambda Alerter ────────────────────────────────────────────────────────────
module "lambda_alerter" {
  source              = "../../modules/lambda_alerter"
  project             = var.project
  environment         = var.environment
  raw_sns_topic_arn   = module.sns.raw_topic_arn
  alert_sns_topic_arn = module.sns.alert_topic_arn
  log_retention_days  = var.log_retention_days
  tags                = local.tags
}

# ── Cost Anomaly Monitor + Subscription ──────────────────────────────────────
module "cost_anomaly" {
  source            = "../../modules/cost_anomaly"
  project           = var.project
  environment       = var.environment
  raw_sns_topic_arn = module.sns.raw_topic_arn
  anomaly_threshold = var.anomaly_threshold
  tags              = local.tags
}
