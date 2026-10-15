# Week 23 -- Service networking with VPC Lattice
#
# One service that only a named identity may call, with the check happening
# before the request reaches any code of mine.
#
# The thing actually being tested is the refusal. Everyone writes the auth
# policy; almost nobody confirms that a request from the wrong identity is
# genuinely turned away, or notices when the policy is attached but inert.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.68, < 7.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "week-23-dev"
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
  name = "week23-lattice"

  tags = {
    Project   = "aws-platform-engineering-lab"
    Week      = "23"
    ManagedBy = "terraform"
  }
}

module "lattice" {
  source = "../../modules/lattice"

  name              = local.name
  tags              = local.tags
  service_auth_type = var.service_auth_type
  lambda_dir        = "${path.root}/../../../lambda"
}
