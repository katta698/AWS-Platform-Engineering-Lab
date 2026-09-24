# Week 20 -- An Accountable Event Bus
#
# An event bus is trivial to deploy and hard to interrogate. Publishing succeeds
# whether or not anything is listening: PutEvents returns HTTP 200 and an event
# id for an event that no rule matches and nobody consumes. There is no error,
# no default metric, and nothing that says a decision was made to discard it.
#
# This build adds the four mechanisms that make the bus answerable, and then
# tries to break the one that is most often assumed rather than tested.
#
#   archive      can I get the event back?
#   discoverer   what did it actually look like?
#   CloudTrail   who published it?          <- only possible since 4 May 2026
#   DLQ          what failed to deliver?
#
# WHAT THE ATTRIBUTION HALF ACTUALLY GIVES YOU, because it is narrower than it
# sounds: a CloudTrail data event carries the caller, the IP, the source, the
# detail-type and the event id -- and redacts the payload
# (`"detail": "HIDDEN_DUE_TO_SECURITY_REASONS"`). The archive carries the
# payload and no identity. WHO and WHAT live in two different systems and join
# on the event id. Neither answers "what happened" on its own.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "week-20-dev"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project   = "aws-platform-engineering-lab"
      Week      = "20"
      ManagedBy = "terraform"
    }
  }
}

locals {
  tags = {
    Project = "aws-platform-engineering-lab"
    Week    = "20"
  }
}

# The bus and its three accountability mechanisms.
#
# Deliberately a CUSTOM bus. The `default` bus already carries every AWS service
# event in this account, so a discoverer pointed at it would infer schemas for
# unrelated traffic and the archive would store it. There is also an unrelated
# `ebs-savings-governance-bus` here from a different project -- neither is this
# lab's to touch.
module "bus" {
  source = "../../modules/event_bus"

  bus_name               = var.bus_name
  archive_retention_days = var.archive_retention_days
  tags                   = local.tags
}

# The subscribers, the catch-all that makes "matched nothing" countable, and the
# alarms that make each silent failure audible.
module "consumers" {
  source = "../../modules/consumers"

  name_prefix        = var.bus_name
  bus_name           = module.bus.bus_name
  log_retention_days = var.log_retention_days
  alert_email        = var.alert_email
  tags               = local.tags
}
