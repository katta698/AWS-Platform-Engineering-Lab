###############################################################################
# Week 6: Account Vending Machine (simulated — no Control Tower)
# ServiceNow ticket → Organizations CreateAccount → poll → MoveAccount into OU
#                    → SCP guardrails apply automatically by OU membership
#
# Must be deployed from the Organizations MANAGEMENT account — organizations:
# CreateAccount / MoveAccount only work there.
###############################################################################

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  cloud {
    organization = "Katta"
    workspaces {
      name = "week-06-dev"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}
data "aws_organizations_organization" "current" {}

data "aws_organizations_organizational_units" "root_children" {
  parent_id = data.aws_organizations_organization.current.roots[0].id
}

locals {
  root_id = data.aws_organizations_organization.current.roots[0].id

  # This Organization already has real accounts/OUs at root (Core-OU,
  # Archived-Accounts, Workloads-OU — residue from a previously decommissioned
  # Control Tower Landing Zone). Vending OUs nest under the existing
  # Workloads-OU instead of root so they don't sit alongside that structure.
  workloads_ou_id = [
    for ou in data.aws_organizations_organizational_units.root_children.children :
    ou.id if ou.name == var.parent_ou_name
  ][0]

  # Deterministic ARNs — breaks Lambda <-> Step Functions circular dependency
  state_machine_arn           = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.project_name}-account-vending-${var.environment}"
  lambda_webhook_receiver_arn = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-webhook-receiver-${var.environment}"
  lambda_account_creator_arn  = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-account-creator-${var.environment}"
  lambda_account_mover_arn    = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-account-mover-${var.environment}"
  lambda_status_notifier_arn  = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-status-notifier-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Week        = "06"
    ManagedBy   = "Terraform"
    Owner       = "jay"
  }
}

# ── SSM Parameters (ServiceNow + webhook HMAC secret) ─────────────────────────
resource "aws_ssm_parameter" "hmac_secret" {
  name  = "/${var.project_name}/${var.environment}/hmac-secret"
  type  = "SecureString"
  value = var.webhook_secret
}

resource "aws_ssm_parameter" "snow_instance" {
  name  = "/${var.project_name}/${var.environment}/snow-instance"
  type  = "SecureString"
  value = var.servicenow_instance
}

resource "aws_ssm_parameter" "snow_user" {
  name  = "/${var.project_name}/${var.environment}/snow-user"
  type  = "SecureString"
  value = var.servicenow_username
}

resource "aws_ssm_parameter" "snow_password" {
  name  = "/${var.project_name}/${var.environment}/snow-password"
  type  = "SecureString"
  value = var.servicenow_password
}

# ── Organizations OUs ──────────────────────────────────────────────────────────
module "organizations" {
  source    = "../../modules/organizations"
  parent_id = local.workloads_ou_id
  ou_names  = var.ou_names
  tags      = local.common_tags
}

# ── SCP guardrails (attached to Sandbox OU) ───────────────────────────────────
module "scp" {
  source          = "../../modules/scp"
  sandbox_ou_id   = module.organizations.ou_ids["Sandbox"]
  allowed_regions = var.allowed_regions

  depends_on = [module.organizations]
}

# ── IAM Roles ──────────────────────────────────────────────────────────────────
module "iam" {
  source       = "../../modules/iam"
  project_name = var.project_name
  environment  = var.environment

  state_machine_arn = local.state_machine_arn
  lambda_arns = {
    account_creator = local.lambda_account_creator_arn
    account_mover   = local.lambda_account_mover_arn
    status_notifier = local.lambda_status_notifier_arn
  }
  tags = local.common_tags
}

# ── Step Functions ─────────────────────────────────────────────────────────────
module "step_functions" {
  source       = "../../modules/step-functions"
  project_name = var.project_name
  environment  = var.environment

  sfn_role_arn               = module.iam.step_functions_role_arn
  account_creator_lambda_arn = local.lambda_account_creator_arn
  account_mover_lambda_arn   = local.lambda_account_mover_arn
  status_notifier_lambda_arn = local.lambda_status_notifier_arn
  tags                       = local.common_tags

  depends_on = [module.iam]
}

# ── Lambda Functions ───────────────────────────────────────────────────────────
module "lambda" {
  source       = "../../modules/lambda"
  project_name = var.project_name
  environment  = var.environment

  webhook_receiver_role_arn = module.iam.webhook_receiver_role_arn
  account_creator_role_arn  = module.iam.account_creator_role_arn
  account_mover_role_arn    = module.iam.account_mover_role_arn
  status_notifier_role_arn  = module.iam.status_notifier_role_arn

  state_machine_arn = local.state_machine_arn
  root_id           = local.root_id
  ou_ids_json       = jsonencode(module.organizations.ou_ids)

  hmac_secret_param   = aws_ssm_parameter.hmac_secret.name
  snow_instance_param = aws_ssm_parameter.snow_instance.name
  snow_user_param     = aws_ssm_parameter.snow_user.name
  snow_password_param = aws_ssm_parameter.snow_password.name

  tags = local.common_tags

  depends_on = [module.iam, module.step_functions, module.organizations]
}

# ── API Gateway ────────────────────────────────────────────────────────────────
module "api_gateway" {
  source       = "../../modules/api-gateway"
  project_name = var.project_name
  environment  = var.environment

  webhook_receiver_arn  = module.lambda.webhook_receiver_arn
  webhook_receiver_name = module.lambda.webhook_receiver_name
  tags                  = local.common_tags

  depends_on = [module.lambda]
}
