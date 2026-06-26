###############################################################################
# Week 7: IAM Identity Center SSO
# Groups + permission sets + cross-account assignments, scoped onto the
# Sandbox/Production accounts vended in Week 6's Account Vending Machine.
#
# Prerequisite (manual, no Terraform resource exists for this step): IAM
# Identity Center must already be enabled for the organization, in the
# management account console, before this can apply.
#
# Must be deployed from the Organizations MANAGEMENT account — Identity
# Center and the Organizations OU/account lookups below only work there.
###############################################################################

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  cloud {
    organization = "Katta"
    workspaces {
      name = "week-07-dev"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

data "aws_organizations_organization" "current" {}

data "aws_ssoadmin_instances" "current" {}

data "aws_organizations_organizational_units" "root_children" {
  parent_id = data.aws_organizations_organization.current.roots[0].id
}

locals {
  workloads_ou_id = [
    for ou in data.aws_organizations_organizational_units.root_children.children :
    ou.id if ou.name == var.parent_ou_name
  ][0]

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Week        = "07"
    ManagedBy   = "Terraform"
    Owner       = "jay"
  }
}

# OUs created by Week 6's Account Vending Machine, nested under Workloads-OU
data "aws_organizations_organizational_units" "vending_ous" {
  parent_id = local.workloads_ou_id
}

locals {
  target_ou_ids = [
    for ou in data.aws_organizations_organizational_units.vending_ous.children :
    ou.id if contains(var.target_ou_names, ou.name)
  ]
}

data "aws_organizations_organizational_unit_child_accounts" "target" {
  for_each  = toset(local.target_ou_ids)
  parent_id = each.value
}

locals {
  target_account_ids = distinct(flatten([
    for ou_id, result in data.aws_organizations_organizational_unit_child_accounts.target :
    [for acct in result.accounts : acct.id]
  ]))
}

module "identity_center" {
  source = "../../modules/identity-center"

  identity_store_id = tolist(data.aws_ssoadmin_instances.current.identity_store_ids)[0]
  instance_arn      = tolist(data.aws_ssoadmin_instances.current.arns)[0]

  target_account_ids = local.target_account_ids
  groups             = var.groups
  users              = var.users
  tags               = local.common_tags
}
