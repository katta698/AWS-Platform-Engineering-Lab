###############################################################################
# Week 16 — AWS DevOps Agent: investigations, and whether to believe them
#
# The question this week answers is not "can an agent investigate an incident"
# -- AWS's marketing answers that. It is "can you trust what it concludes, and
# how would you know". An investigating agent does not return a metric, it
# returns a NARRATIVE, and narratives are persuasive whether or not they are
# correct.
#
# So the build is an evaluation harness, not a demo:
#
#   1. a workload that can be broken in a known, specific way
#   2. an agent space pointed at it
#   3. ServiceNow, so findings land where on-call would actually see them
#   4. the agent's conclusion graded against Week 15's CloudTrail attribution,
#      which is ground truth rather than opinion
#
# TWO PROVIDERS, ON PURPOSE
#
# aws   for everything that has existed long enough to have a provider resource
# awscc for the DevOps Agent itself, because hashicorp/aws has no
#       aws_devopsagent_* resources yet (issue #46894 open at time of writing).
#       See modules/agent_space/main.tf for the full reasoning.
###############################################################################

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.98"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "week-16-dev"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

# awscc takes no default_tags -- tags are passed per resource as a key/value
# list, which is why the agent_space module converts a map into that shape.
provider "awscc" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "week16-agent"

  tags = {
    Project     = "AWS-Platform-Engineering-Lab"
    Week        = "16"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

###############################################################################
# The agent space — the boundary
###############################################################################

module "agent_space" {
  source = "../../modules/agent_space"

  name        = local.name_prefix
  description = "Week 16 lab: investigates a deliberately broken workload; findings graded against CloudTrail."
  tags        = local.tags
}

###############################################################################
# The workload the agent is meant to reason about
#
# Deliberately small and deliberately breakable. The point is not to build
# something impressive -- it is to have a failure whose true cause is known
# before the agent is asked, so its answer can be marked rather than admired.
###############################################################################

module "observed_workload" {
  source = "../../modules/observed_workload"

  name_prefix = local.name_prefix
  tags        = local.tags
}
