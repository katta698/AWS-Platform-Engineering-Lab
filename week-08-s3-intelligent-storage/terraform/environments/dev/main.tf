terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  cloud {
    organization = "Katta"
    workspaces {
      name = "week-08-dev"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# Break the circular dependency (s3-storage needs SQS ARN; cost-automation needs
# bucket ARN) by computing both deterministically from known values.
# Neither module needs to wait for the other's output — Terraform plans in parallel.
locals {
  account_id  = data.aws_caller_identity.current.account_id
  name_prefix = "${var.project}-${var.environment}"

  # Matches the bucket name formula in modules/s3-storage/main.tf
  bucket_name = "${local.name_prefix}-${local.account_id}"
  bucket_arn  = "arn:aws:s3:::${local.bucket_name}"

  # Matches the SQS queue name formula in modules/cost-automation/main.tf
  sqs_queue_name = "${local.name_prefix}-object-events"
  sqs_queue_arn  = "arn:aws:sqs:${var.aws_region}:${local.account_id}:${local.sqs_queue_name}"
}

module "cost_automation" {
  source = "../../modules/cost-automation"

  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region
  sns_email   = var.sns_email
  bucket_name = local.bucket_name
  bucket_arn  = local.bucket_arn

  reporter_schedule = "rate(1 day)"
}

module "s3_storage" {
  source = "../../modules/s3-storage"

  project     = var.project
  environment = var.environment
  account_id  = local.account_id

  sqs_queue_arn = local.sqs_queue_arn

  # S3 bucket notification validation requires the SQS queue policy to exist first.
  # Without this, AWS rejects PutBucketNotificationConfiguration with InvalidArgument.
  depends_on = [module.cost_automation]

  intelligent_tiering_archive_days      = var.intelligent_tiering_archive_days
  intelligent_tiering_deep_archive_days = var.intelligent_tiering_deep_archive_days
  logs_ia_transition_days               = var.logs_ia_transition_days
  logs_glacier_transition_days          = var.logs_glacier_transition_days
  logs_expiration_days                  = var.logs_expiration_days
  noncurrent_version_expiration_days    = var.noncurrent_version_expiration_days
}
