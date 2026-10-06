# Week 22 -- Container Image Security Pipeline
#
# No image reaches a deployment unless this pipeline signed it and a scanner
# cleared it -- and both facts are provable for any image in the registry.
#
# The thing actually being tested is the enforcement. Signing and scanning are
# both one-click managed features that produce evidence and stop nothing.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.67, < 7.0"
    }

    # ECR managed signing shipped in November 2025 and still has no resource
    # in the AWS provider -- hashicorp/terraform-provider-aws#47527 was open
    # against 6.67.0, the latest release. Cloud Control carries
    # AWS::ECR::SigningConfiguration, so the feature is manageable
    # declaratively today without waiting for the native resource.
    awscc = {
      source  = "hashicorp/awscc"
      version = ">= 1.104"
    }

    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "week-22-dev"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

provider "awscc" {
  region = var.region
}

locals {
  name = "week22-imagesec"

  tags = {
    Project   = "aws-platform-engineering-lab"
    Week      = "22"
    ManagedBy = "terraform"
  }
}

module "image_pipeline" {
  source = "../../modules/image_pipeline"

  name              = local.name
  tags              = local.tags
  filter_prefix     = var.filter_prefix
  alert_email       = var.alert_email
  lambda_source_dir = "${path.root}/../../../lambda/image_gate"
  docker_dir        = "${path.root}/../../../docker"
}
