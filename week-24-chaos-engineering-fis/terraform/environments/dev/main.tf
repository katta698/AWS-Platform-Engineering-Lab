# Week 24 -- Chaos engineering with AWS FIS
#
# Everyone configures a stop condition and feels safe. A stop condition is a
# CloudWatch alarm, and an alarm cannot fire faster than its own evaluation
# window -- so the safety net has a hole in it the exact size of that window,
# and nobody measures it.
#
# This builds one ordinary service and breaks it three times:
#
#   recovery     no stop condition  -- how long does ECS take by itself?
#   fast         60s / 1 datapoint  -- net catches in about a minute
#   typical      300s / 2 datapoints -- net cannot catch inside ten minutes
#
# The two guarded experiments are identical except for which alarm guards
# them, so the difference in damage duration is attributable to the alarm and
# nothing else.
#
# What this is NOT: a claim that fast alarms are correct. A 60-second alarm on
# a noisy metric pages people at 3am for nothing. The point is that the same
# alarm is doing two jobs -- telling a human, and bounding an experiment --
# and the setting that is right for the first can be badly wrong for the
# second.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "week-24-dev"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  name = "week24-chaos"

  tags = {
    Project = "aws-platform-engineering-lab"
    Week    = "24"
    Purpose = "chaos-engineering-fis"
  }
}

# Default VPC on purpose -- a NAT gateway would cost more than everything else
# in this build combined, and the tasks only pull a public image.
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

  desired_count = var.desired_count
  tags          = local.tags
}

module "chaos" {
  source = "../../modules/chaos"

  name         = local.name
  region       = var.region
  account_id   = data.aws_caller_identity.current.account_id
  cluster_name = module.service.cluster_name
  service_name = module.service.service_name

  fault_percent = var.fault_percent

  # The map keys become the experiment labels used by scripts/run-experiment.sh.
  stop_condition_alarms = {
    fast    = module.service.alarm_fast_arn
    typical = module.service.alarm_typical_arn
  }

  tags = local.tags
}
