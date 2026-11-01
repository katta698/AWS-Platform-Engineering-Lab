# ── Cross-account IAM roles via CloudFormation StackSet ──────────────────────
#
# Deploys EBSDashboardReadRole into every active AWS Organizations member account
# so the Phase 2 Lambda can assume it and call ec2:Describe* cross-account.
#
# Prerequisites:
#   1. Run from the AWS management (payer) account
#   2. AWS Organizations trusted access for CloudFormation must be enabled:
#        aws organizations enable-aws-service-principal \
#          --service-principal cloudformation.amazonaws.com
#   3. Set lambda_role_arn = the Lambda execution role ARN from Phase 2 outputs
#
# Usage:
#   cd infra/cross_account_roles
#   terraform init
#   terraform apply -var="lambda_role_arn=arn:aws:iam::123456789012:role/ebsp2-lambda-role"

terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ── Variables ─────────────────────────────────────────────────────────────────

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "lambda_role_arn" {
  type        = string
  description = "ARN of the Phase 2 Lambda execution role that will assume this role"
}

variable "role_name" {
  type    = string
  default = "EBSDashboardReadRole"
}

variable "target_org_id" {
  type        = string
  description = "AWS Organizations root ID (r-xxxx) or OU ID (ou-xxxx-xxxxxxxx) to deploy into"
  default     = ""
}

variable "target_account_ids" {
  type        = list(string)
  description = "Explicit list of account IDs to deploy into (leave empty to use target_org_id)"
  default     = []
}

# ── Data sources ──────────────────────────────────────────────────────────────

data "aws_organizations_organization" "current" {}

locals {
  # Use explicit accounts if provided, otherwise deploy org-wide
  deploy_to_org      = length(var.target_account_ids) == 0
  org_root_id        = data.aws_organizations_organization.current.roots[0].id
  target_org_unit_id = var.target_org_id != "" ? var.target_org_id : local.org_root_id
}

# ── CloudFormation StackSet ───────────────────────────────────────────────────

resource "aws_cloudformation_stack_set" "ebs_read_role" {
  name             = "ebs-dashboard-read-role"
  description      = "Read-only EC2/EBS role for EBS Savings Dashboard Lambda"
  permission_model = "SERVICE_MANAGED" # Uses Organizations — no manual admin role needed

  auto_deployment {
    enabled                          = true  # auto-deploys to new accounts that join the org
    retain_stacks_on_account_removal = false # cleans up when account leaves org
  }

  capabilities = ["CAPABILITY_NAMED_IAM"]

  template_body = jsonencode({
    AWSTemplateFormatVersion = "2010-09-09"
    Description              = "EBS Dashboard read-only cross-account role"
    Parameters = {
      LambdaRoleArn = {
        Type        = "String"
        Description = "ARN of the Lambda role allowed to assume this role"
      }
      RoleName = {
        Type    = "String"
        Default = var.role_name
      }
    }
    Resources = {
      EBSDashboardReadRole = {
        Type = "AWS::IAM::Role"
        Properties = {
          RoleName = { Ref = "RoleName" }
          AssumeRolePolicyDocument = {
            Version = "2012-10-17"
            Statement = [{
              Effect    = "Allow"
              Principal = { AWS = { Ref = "LambdaRoleArn" } }
              Action    = "sts:AssumeRole"
              Condition = {
                # Restrict to calls from within the same org — defence in depth
                StringEquals = {
                  "aws:PrincipalOrgID" = data.aws_organizations_organization.current.id
                }
              }
            }]
          }
          Policies = [{
            PolicyName = "EBSReadOnly"
            PolicyDocument = {
              Version = "2012-10-17"
              Statement = [{
                Effect = "Allow"
                Action = [
                  "ec2:DescribeVolumes",
                  "ec2:DescribeInstances",
                  "ec2:DescribeSnapshots",
                  "ec2:DescribeVolumeStatus",
                  "ec2:DescribeTags"
                ]
                Resource = "*"
              }]
            }
          }]
          Tags = [
            { Key = "ManagedBy", Value = "terraform" },
            { Key = "Project", Value = "ebs-dashboard" }
          ]
        }
      }
    }
    Outputs = {
      RoleArn = {
        Value       = { "Fn::GetAtt" = ["EBSDashboardReadRole", "Arn"] }
        Description = "ARN of the EBS Dashboard read role"
      }
    }
  })

  parameters = {
    LambdaRoleArn = var.lambda_role_arn
    RoleName      = var.role_name
  }

  tags = {
    Project   = "ebs-dashboard"
    ManagedBy = "terraform"
  }

  lifecycle {
    # Template body changes require destroy+recreate of instances — warn explicitly
    create_before_destroy = false
  }
}

# ── StackSet Instances ────────────────────────────────────────────────────────
# Option A: Deploy to entire org (or a specific OU)

resource "aws_cloudformation_stack_set_instance" "org_wide" {
  count = local.deploy_to_org ? 1 : 0

  stack_set_name = aws_cloudformation_stack_set.ebs_read_role.name
  region         = var.aws_region

  deployment_targets {
    organizational_unit_ids = [local.target_org_unit_id]
  }

  operation_preferences {
    max_concurrent_percentage    = 100 # deploy to all accounts in parallel
    failure_tolerance_percentage = 10  # allow up to 10% of accounts to fail
    region_concurrency_type      = "PARALLEL"
  }
}

# Option B: Deploy to explicit account list (uncomment target_account_ids var above)

resource "aws_cloudformation_stack_set_instance" "specific_accounts" {
  for_each = local.deploy_to_org ? {} : toset(var.target_account_ids)

  stack_set_name = aws_cloudformation_stack_set.ebs_read_role.name
  account_id     = each.value
  region         = var.aws_region

  operation_preferences {
    max_concurrent_count    = 10
    failure_tolerance_count = 2
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "stack_set_name" {
  value       = aws_cloudformation_stack_set.ebs_read_role.name
  description = "CloudFormation StackSet name"
}

output "role_name" {
  value       = var.role_name
  description = "IAM role name deployed in every member account"
}

output "role_arn_pattern" {
  value       = "arn:aws:iam::ACCOUNT_ID:role/${var.role_name}"
  description = "Role ARN pattern — replace ACCOUNT_ID per member account"
}

output "org_id" {
  value       = data.aws_organizations_organization.current.id
  description = "AWS Organization ID (used in PrincipalOrgID condition)"
}
