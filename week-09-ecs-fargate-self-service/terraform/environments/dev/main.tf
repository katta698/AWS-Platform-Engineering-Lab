###############################################################################
# Week 9: ECS Fargate Self-Service
# ServiceNow ticket -> Step Functions -> fargate_provisioner creates an ECR
# repo, task definition, ECS service, ALB target group + path rule, and
# auto-scaling target -> ticket closes with the live path-routed URL.
###############################################################################

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  cloud {
    organization = "Katta"
    workspaces {
      name = "week-09-dev"
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

locals {
  # Deterministic ARNs — breaks the Lambda <-> Step Functions circular
  # dependency the same way Week 6 and Week 8 did: both sides compute the
  # same ARN from account ID + fixed naming instead of relying on a resource
  # output the other side hasn't created yet.
  state_machine_arn              = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.project_name}-provisioning-${var.environment}"
  lambda_webhook_receiver_arn    = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-webhook-receiver-${var.environment}"
  lambda_fargate_provisioner_arn = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-fargate-provisioner-${var.environment}"
  lambda_status_notifier_arn     = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-status-notifier-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Week        = "09"
    ManagedBy   = "Terraform"
    Owner       = "jay"
  }
}

# ── SSM Parameters (ServiceNow creds + webhook HMAC secret) ──────────────────
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

# ── Networking ─────────────────────────────────────────────────────────────
module "vpc" {
  source = "../../modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  availability_zones = var.availability_zones
  tags               = local.common_tags
}

module "security_groups" {
  source = "../../modules/security-groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  tags         = local.common_tags
}

# VPC endpoints live here, not inside the vpc module — they need the
# vpc-endpoints security group, which itself needs the VPC's ID, so building
# them inside the vpc module would make vpc <-> security-groups circular.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = module.vpc.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [module.vpc.private_route_table_id]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpce-s3"
  })
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.api"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnet_ids
  security_group_ids  = [module.security_groups.vpc_endpoints_sg_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpce-ecr-api"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.ecr.dkr"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnet_ids
  security_group_ids  = [module.security_groups.vpc_endpoints_sg_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpce-ecr-dkr"
  })
}

resource "aws_vpc_endpoint" "logs" {
  vpc_id              = module.vpc.vpc_id
  service_name        = "com.amazonaws.${var.aws_region}.logs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.vpc.private_subnet_ids
  security_group_ids  = [module.security_groups.vpc_endpoints_sg_id]
  private_dns_enabled = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-vpce-logs"
  })
}

# ── ECS Cluster ────────────────────────────────────────────────────────────
module "ecs_cluster" {
  source = "../../modules/ecs-cluster"

  project_name = var.project_name
  environment  = var.environment
  tags         = local.common_tags
}

# ── Shared ALB ─────────────────────────────────────────────────────────────
module "alb" {
  source = "../../modules/alb"

  project_name      = var.project_name
  environment       = var.environment
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security_groups.alb_sg_id
  tags              = local.common_tags
}

# ── IAM Roles ──────────────────────────────────────────────────────────────
module "iam" {
  source = "../../modules/iam"

  project_name      = var.project_name
  environment       = var.environment
  cluster_name      = module.ecs_cluster.cluster_name
  state_machine_arn = local.state_machine_arn
  lambda_arns = {
    webhook_receiver    = local.lambda_webhook_receiver_arn
    fargate_provisioner = local.lambda_fargate_provisioner_arn
    status_notifier     = local.lambda_status_notifier_arn
  }
  tags = local.common_tags
}

# ── Step Functions ─────────────────────────────────────────────────────────
module "step_functions" {
  source = "../../modules/step-functions"

  project_name                   = var.project_name
  environment                    = var.environment
  sfn_role_arn                   = module.iam.step_functions_role_arn
  fargate_provisioner_lambda_arn = local.lambda_fargate_provisioner_arn
  status_notifier_lambda_arn     = local.lambda_status_notifier_arn
  tags                           = local.common_tags

  depends_on = [module.iam]
}

# ── Lambda Functions ───────────────────────────────────────────────────────
module "lambda" {
  source = "../../modules/lambda"

  project_name = var.project_name
  environment  = var.environment

  webhook_receiver_role_arn    = module.iam.webhook_receiver_role_arn
  fargate_provisioner_role_arn = module.iam.fargate_provisioner_role_arn
  status_notifier_role_arn     = module.iam.status_notifier_role_arn

  state_machine_arn = local.state_machine_arn
  hmac_secret_param = aws_ssm_parameter.hmac_secret.name

  cluster_name                = module.ecs_cluster.cluster_name
  cluster_arn                 = module.ecs_cluster.cluster_arn
  private_subnet_ids          = module.vpc.private_subnet_ids
  ecs_tasks_sg_id             = module.security_groups.ecs_tasks_sg_id
  ecs_task_execution_role_arn = module.iam.ecs_task_execution_role_arn
  alb_listener_arn            = module.alb.listener_arn
  alb_dns_name                = module.alb.alb_dns_name
  vpc_id                      = module.vpc.vpc_id

  snow_instance_param = aws_ssm_parameter.snow_instance.name
  snow_user_param     = aws_ssm_parameter.snow_user.name
  snow_password_param = aws_ssm_parameter.snow_password.name

  tags = local.common_tags

  depends_on = [module.iam, module.step_functions, module.ecs_cluster, module.alb]
}

# ── API Gateway ────────────────────────────────────────────────────────────
module "api_gateway" {
  source = "../../modules/api-gateway"

  project_name          = var.project_name
  environment           = var.environment
  webhook_receiver_arn  = module.lambda.webhook_receiver_arn
  webhook_receiver_name = module.lambda.webhook_receiver_name
  tags                  = local.common_tags

  depends_on = [module.lambda]
}
