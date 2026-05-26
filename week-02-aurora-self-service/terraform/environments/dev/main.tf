###############################################################################
# Week 2: Aurora Self-Service Platform — dev environment
# Shared Aurora Serverless v2 cluster, unlimited tenant databases
###############################################################################

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    bucket       = "jay-terraformstate-bucket"
    key          = "week-02-aurora-self-service/dev/terraform.tfstate"
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
  # Compute state machine ARN deterministically — breaks the Lambda ↔ Step Functions cycle
  state_machine_arn = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.project}-${var.environment}-db-provisioning"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    Week        = "02"
    ManagedBy   = "Terraform"
    Owner       = "jay"
  }
}

# ── SNS Alert Topic ────────────────────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "${var.project}-${var.environment}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── SSM Parameters (ServiceNow + webhook secret) ──────────────────────────────
resource "aws_ssm_parameter" "servicenow_instance" {
  name  = "/${var.project}/${var.environment}/servicenow/instance_url"
  type  = "SecureString"
  value = var.servicenow_instance_url
}

resource "aws_ssm_parameter" "servicenow_username" {
  name  = "/${var.project}/${var.environment}/servicenow/username"
  type  = "SecureString"
  value = var.servicenow_username
}

resource "aws_ssm_parameter" "servicenow_password" {
  name  = "/${var.project}/${var.environment}/servicenow/password"
  type  = "SecureString"
  value = var.servicenow_password
}

resource "aws_ssm_parameter" "webhook_secret" {
  name  = "/${var.project}/${var.environment}/webhook/secret"
  type  = "SecureString"
  value = var.webhook_secret
}

# ── VPC ────────────────────────────────────────────────────────────────────────
module "vpc" {
  source      = "../../modules/vpc"
  project     = var.project
  environment = var.environment
  tags        = local.common_tags
}

# ── Step Functions (placeholder ARN — resolved after real apply order) ─────────
# We use a two-pass apply: first create Aurora + VPC + Secrets,
# then Step Functions + Lambda + API Gateway.
# For single-pass apply, use -target ordering or module depends_on.

module "step_functions" {
  source      = "../../modules/step-functions"
  project     = var.project
  environment = var.environment

  db_provisioner_arn      = module.lambda.db_provisioner_arn
  status_updater_arn      = module.lambda.status_updater_arn
  cluster_reader_endpoint = module.aurora.cluster_reader_endpoint
  alert_sns_topic_arn     = aws_sns_topic.alerts.arn
  tags                    = local.common_tags
}

# ── Aurora Serverless v2 ───────────────────────────────────────────────────────
module "aurora" {
  source      = "../../modules/aurora"
  project     = var.project
  environment = var.environment

  db_subnet_group_name     = module.vpc.db_subnet_group_name
  aurora_security_group_id = module.vpc.aurora_security_group_id
  master_username          = var.master_username
  master_password          = var.master_password
  min_capacity             = var.aurora_min_capacity
  max_capacity             = var.aurora_max_capacity
  alert_sns_topic_arn      = aws_sns_topic.alerts.arn
  tags                     = local.common_tags

  depends_on = [module.vpc]
}

# ── Secrets Manager ────────────────────────────────────────────────────────────
module "secrets" {
  source      = "../../modules/secrets"
  project     = var.project
  environment = var.environment

  cluster_endpoint         = module.aurora.cluster_endpoint
  cluster_port             = module.aurora.cluster_port
  master_username          = var.master_username
  master_password          = var.master_password
  database_name            = module.aurora.database_name
  vpc_id                   = module.vpc.vpc_id
  lambda_subnet_ids        = module.vpc.private_subnet_ids
  lambda_security_group_id = module.vpc.lambda_security_group_id
  tags                     = local.common_tags

  depends_on = [module.aurora]
}

# ── Lambda Functions ───────────────────────────────────────────────────────────
module "lambda" {
  source      = "../../modules/lambda"
  project     = var.project
  environment = var.environment

  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.private_subnet_ids
  security_group_id = module.vpc.lambda_security_group_id

  state_machine_arn       = local.state_machine_arn
  master_secret_arn       = module.secrets.master_secret_arn
  rotation_lambda_arn     = module.secrets.rotation_lambda_arn
  cluster_endpoint        = module.aurora.cluster_endpoint
  cluster_reader_endpoint = module.aurora.cluster_reader_endpoint

  webhook_secret_param      = aws_ssm_parameter.webhook_secret.name
  servicenow_instance_param = aws_ssm_parameter.servicenow_instance.name
  servicenow_username_param = aws_ssm_parameter.servicenow_username.name
  servicenow_password_param = aws_ssm_parameter.servicenow_password.name

  pg8000_layer_arn = var.pg8000_layer_arn
  tags             = local.common_tags

  depends_on = [module.secrets, module.vpc]
}

# ── API Gateway ────────────────────────────────────────────────────────────────
module "api_gateway" {
  source      = "../../modules/api-gateway"
  project     = var.project
  environment = var.environment

  webhook_receiver_arn  = module.lambda.webhook_receiver_arn
  webhook_receiver_name = module.lambda.webhook_receiver_name
  tags                  = local.common_tags

  depends_on = [module.lambda]
}
