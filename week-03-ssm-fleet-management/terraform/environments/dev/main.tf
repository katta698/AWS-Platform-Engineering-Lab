###############################################################################
# Week 3: SSM Fleet Management Platform — dev environment
###############################################################################

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    bucket       = "jay-terraformstate-bucket"
    key          = "week-03-ssm-fleet-management/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    Week        = "03"
    ManagedBy   = "terraform"
    Owner       = "jay-katta"
  }
}

# ── VPC + SSM endpoints ───────────────────────────────────────────────────────
module "vpc" {
  source      = "../../modules/vpc"
  project     = var.project
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
}

# ── IAM roles ─────────────────────────────────────────────────────────────────
module "iam" {
  source                 = "../../modules/iam"
  project                = var.project
  environment            = var.environment
  session_logs_bucket_arn = module.ssm.session_logs_bucket_arn
}

# ── SSM platform ──────────────────────────────────────────────────────────────
module "ssm" {
  source                      = "../../modules/ssm"
  project                     = var.project
  environment                 = var.environment
  maintenance_window_role_arn = module.iam.maintenance_window_role_arn
}

# ── EC2 fleet ─────────────────────────────────────────────────────────────────
module "ec2_fleet" {
  source                = "../../modules/ec2-fleet"
  project               = var.project
  environment           = var.environment
  instance_type         = var.instance_type
  desired_capacity      = var.desired_capacity
  min_size              = var.min_size
  max_size              = var.max_size
  private_subnet_ids    = module.vpc.private_subnet_ids
  ec2_sg_id             = module.vpc.ec2_sg_id
  instance_profile_name = module.iam.ec2_instance_profile_name
}

# ── Step Functions (ARN computed before Lambda to break circular dep) ─────────
locals {
  state_machine_arn = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.project}-${var.environment}-fleet-management"
}

# ── Lambda functions ──────────────────────────────────────────────────────────
module "lambda" {
  source                    = "../../modules/lambda"
  project                   = var.project
  environment               = var.environment
  lambda_role_arn           = module.iam.lambda_role_arn
  state_machine_arn         = local.state_machine_arn
  webhook_secret            = var.webhook_secret
  servicenow_instance_url   = var.servicenow_instance_url
  servicenow_username       = var.servicenow_username
  servicenow_password       = var.servicenow_password
  ssm_automation_role_arn   = module.iam.ssm_automation_role_arn
  onboard_document_name     = module.ssm.onboard_document_name
  patch_fleet_document_name = module.ssm.patch_fleet_document_name
}

# ── Step Functions state machine ──────────────────────────────────────────────
module "step_functions" {
  source                  = "../../modules/step-functions"
  project                 = var.project
  environment             = var.environment
  sfn_role_arn            = module.iam.step_functions_role_arn
  fleet_onboarder_arn     = module.lambda.fleet_onboarder_arn
  patch_orchestrator_arn  = module.lambda.patch_orchestrator_arn
  status_updater_arn      = module.lambda.status_updater_arn
}

# ── API Gateway ───────────────────────────────────────────────────────────────
module "api_gateway" {
  source                         = "../../modules/api-gateway"
  project                        = var.project
  environment                    = var.environment
  webhook_receiver_invoke_arn    = module.lambda.webhook_receiver_arn
  webhook_receiver_function_name = "${var.project}-${var.environment}-webhook-receiver"

  depends_on = [module.lambda]
}

# ── CloudWatch dashboard + alarms ─────────────────────────────────────────────
module "cloudwatch" {
  source            = "../../modules/cloudwatch"
  project           = var.project
  environment       = var.environment
  alert_email       = var.alert_email
  state_machine_arn = module.step_functions.state_machine_arn
}
