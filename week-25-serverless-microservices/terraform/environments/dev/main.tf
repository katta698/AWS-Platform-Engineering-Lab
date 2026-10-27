# Week 25 -- three serverless microservices that share one concurrency pool.
#
# WHY us-east-2 AND NOT us-east-1 LIKE EVERY OTHER WEEK
# -----------------------------------------------------
# Lambda's concurrency limit is per account AND PER REGION: 1,000 concurrent
# executions by default, shared by every function without a reservation.
#
# us-east-1 in this account holds 13 Lambda functions from other projects --
# the blog search indexer among them -- all drawing on that one unreserved
# pool. This week deliberately exhausts the pool, so running it there would
# throttle them. Measured before choosing:
#
#   us-east-1   13 functions   quota 1000
#   us-east-2    0 functions   quota 1000     <- empty, and its own pool
#
# So the lab runs in us-east-2, where the entire unreserved pool belongs to the
# experiment and there are no bystanders. The test is more honest for it: the
# pool is genuinely exhausted rather than fenced down to a slice.
#
# That is also the first finding of the week, before any code runs. Concurrency
# is a regional pool, which makes region choice a blast-radius decision rather
# than a latency one.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "week-25-dev"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

locals {
  name = "week25-microservices"
  tags = {
    Week    = "25"
    Project = "aws-platform-engineering-lab"
    Managed = "terraform"
  }
}

module "service" {
  source = "../../modules/service"

  name = local.name
  tags = local.tags

  checkout_duration_ms  = var.checkout_duration_ms
  neighbour_duration_ms = var.neighbour_duration_ms

  # The control variable. Reserved concurrency is an attribute of the Lambda
  # function, not a resource of its own, so it has to be set where the
  # function is declared rather than in the experiment module.
  protect_checkout              = var.protect_checkout
  checkout_reserved_concurrency = var.checkout_reserved_concurrency
}

module "experiment" {
  source = "../../modules/experiment"

  name           = local.name
  tags           = local.tags
  function_names = module.service.function_names
  region         = var.region
}
