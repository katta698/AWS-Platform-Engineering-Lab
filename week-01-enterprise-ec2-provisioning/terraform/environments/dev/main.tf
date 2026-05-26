###############################################################################
# Root Configuration — Dev Environment
# Composes all modules for Enterprise EC2 Provisioning
###############################################################################

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "jay-terraformstate-bucket"
    key          = "week-01-enterprise-ec2/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true # S3 native locking (Terraform 1.10+) — DynamoDB no longer needed
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "platform-engineering"
      CostCenter  = var.cost_center
      SnTicket    = var.servicenow_ticket_id # Written by Lambda before apply
    }
  }
}

# ── Data ─────────────────────────────────────────────────────────────────────
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"] # Excludes Local Zones and Wavelength Zones
  }
}

locals {
  az_count = min(2, length(data.aws_availability_zones.available.names))
  azs      = slice(data.aws_availability_zones.available.names, 0, local.az_count)
}

# ── Modules ──────────────────────────────────────────────────────────────────

module "vpc" {
  source = "../../modules/vpc"

  project              = var.project
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  public_subnet_cidrs  = [cidrsubnet(var.vpc_cidr, 8, 1), cidrsubnet(var.vpc_cidr, 8, 2)]
  private_subnet_cidrs = [cidrsubnet(var.vpc_cidr, 8, 11), cidrsubnet(var.vpc_cidr, 8, 12)]
  availability_zones   = local.azs
  enable_nat_gateway   = true
  enable_flow_logs     = true
  tags                 = local.common_tags
}

module "security_groups" {
  source = "../../modules/security_groups"

  project     = var.project
  environment = var.environment
  vpc_id      = module.vpc.vpc_id
  app_port    = var.app_port
  tags        = local.common_tags
}

module "iam" {
  source = "../../modules/iam"

  project                     = var.project
  environment                 = var.environment
  artifact_bucket_name        = var.artifact_bucket_name
  tf_state_bucket             = var.tf_state_bucket
  tf_lock_table               = "n/a" # S3 native locking used — no DynamoDB table
  github_org                  = var.github_org
  github_repo                 = var.github_repo
  create_github_oidc_provider = var.create_github_oidc_provider
  existing_oidc_provider_arn  = var.existing_oidc_provider_arn
  tags                        = local.common_tags
}

module "sns" {
  source = "../../modules/sns"

  project      = var.project
  environment  = var.environment
  alert_emails = var.alert_emails
  tags         = local.common_tags
}

module "alb" {
  source = "../../modules/alb"

  project           = var.project
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security_groups.alb_sg_id
  app_port          = var.app_port
  health_check_path = var.health_check_path
  tags              = local.common_tags
}

module "asg" {
  source = "../../modules/asg"

  project               = var.project
  environment           = var.environment
  aws_region            = var.aws_region
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  ec2_sg_id             = module.security_groups.ec2_sg_id
  target_group_arn      = module.alb.target_group_arn
  instance_profile_name = module.iam.ec2_instance_profile_name
  instance_type         = var.instance_type
  root_volume_size      = var.root_volume_size
  app_port              = var.app_port
  min_size              = var.asg_min_size
  max_size              = var.asg_max_size
  desired_capacity      = var.asg_desired_capacity
  tags                  = local.common_tags
}

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  project                 = var.project
  environment             = var.environment
  aws_region              = var.aws_region
  alb_arn_suffix          = module.alb.alb_arn
  target_group_arn_suffix = module.alb.target_group_arn
  asg_name                = module.asg.asg_name
  sns_topic_arn           = module.sns.topic_arn
  log_retention_days      = var.log_retention_days
  tags                    = local.common_tags
}

# ── Step Functions (depends on Lambda ARNs) ───────────────────────────────────
module "step_functions" {
  source = "../../modules/step_functions"

  project                = var.project
  environment            = var.environment
  status_updater_arn     = module.lambda.status_updater_arn
  deployment_trigger_arn = module.lambda.deployment_trigger_arn
  tags                   = local.common_tags
}

# ── API Gateway (depends on Lambda invoke ARN) ────────────────────────────────
module "api_gateway" {
  source = "../../modules/api_gateway"

  project           = var.project
  environment       = var.environment
  lambda_invoke_arn = module.lambda.servicenow_receiver_invoke_arn
  tags              = local.common_tags
}

# ── Lambda (depends on Step Functions ARN + API Gateway ARN) ─────────────────
# Note: circular dependency resolved by using placeholder ARN for API GW first,
# then Lambda permission is added after API GW is created.
module "lambda" {
  source = "../../modules/lambda"

  project                   = var.project
  environment               = var.environment
  state_machine_arn         = module.step_functions.state_machine_arn
  api_gateway_execution_arn = module.api_gateway.execution_arn
  github_org                = var.github_org
  github_repo               = var.github_repo
  log_retention_days        = var.log_retention_days
  tags                      = local.common_tags
}

# ── SSM Parameters — ServiceNow + GitHub credentials ─────────────────────────
resource "aws_ssm_parameter" "servicenow_instance" {
  name  = "/${var.project}/${var.environment}/servicenow/instance_url"
  type  = "String"
  value = var.servicenow_instance_url
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "servicenow_username" {
  name  = "/${var.project}/${var.environment}/servicenow/username"
  type  = "String"
  value = var.servicenow_username
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "servicenow_password" {
  name  = "/${var.project}/${var.environment}/servicenow/password"
  type  = "SecureString"
  value = var.servicenow_password
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "github_token" {
  name  = "/${var.project}/${var.environment}/github/token"
  type  = "SecureString"
  value = var.github_token
  tags  = local.common_tags
}

resource "aws_ssm_parameter" "webhook_secret" {
  name  = "/${var.project}/${var.environment}/webhook/secret"
  type  = "SecureString"
  value = var.webhook_secret
  tags  = local.common_tags
}

locals {
  common_tags = {
    Project          = var.project
    Environment      = var.environment
    ManagedBy        = "Terraform"
    Owner            = "platform-engineering"
    CostCenter       = var.cost_center
    ServiceNowTicket = var.servicenow_ticket_id
  }
}
