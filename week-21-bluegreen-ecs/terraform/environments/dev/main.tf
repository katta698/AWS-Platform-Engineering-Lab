# Week 21 -- Blue/Green Deployments on ECS
#
# Deploy a new version with no downtime, and get the old one back
# automatically when the new one is bad. The deployment controller is ECS
# itself: no CodeDeploy, because AWS recommends the native path for new work
# as of March 2026 and it removes a service from the failure path.
#
# The thing actually being tested is the rollback. Everyone configures it;
# almost nobody fires it on purpose.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"

      # >= 6.4 is not cosmetic. deployment_configuration with
      # strategy = "BLUE_GREEN" landed in provider 6.4.0; on 6.0-6.3 the block
      # is silently unknown and the service deploys as a rolling update.
      version = ">= 6.4, < 7.0"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "week-21-dev"
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
  name = "week21-bluegreen"

  tags = {
    Project   = "aws-platform-engineering-lab"
    Week      = "21"
    ManagedBy = "terraform"
  }
}

# Default VPC, deliberately. A NAT gateway would cost more per hour than
# everything else in this build combined, and the tasks only pull a public
# image. Production puts these in private subnets.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

module "service" {
  source = "../../modules/service"

  name       = local.name
  region     = var.region
  vpc_id     = data.aws_vpc.default.id
  subnet_ids = slice(sort(data.aws_subnets.default.ids), 0, 2) # ALB needs two AZs

  app_version          = var.app_version
  serve_root           = var.serve_root
  bake_time_in_minutes = var.bake_time_in_minutes

  tags = local.tags
}
