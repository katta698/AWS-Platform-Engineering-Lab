# Week 17 — MCP Server for Platform Operations
#
# An MCP server that answers, in plain English, the question that took eleven
# API calls on 2026-08-30: what is running, what is it costing, and did we
# leave anything behind.
#
# The roadmap originally planned this server over Weeks 10-16's own data. That
# data no longer exists -- those weeks were destroyed on 2026-08-30 once their
# free trials expired and they started billing -- so the server reads live AWS
# control-plane state instead. Same topic, a data source that cannot evaporate.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.7"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "week-17-dev"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "aws-platform-engineering-lab"
      Week      = "17"
      ManagedBy = "terraform"
    }
  }
}

module "mcp_server" {
  source = "../../modules/mcp_server"

  name_prefix         = var.name_prefix
  log_retention_days  = var.log_retention_days
  cache_ttl_seconds   = var.cache_ttl_seconds
  alarm_sns_topic_arn = var.alarm_sns_topic_arn
}
