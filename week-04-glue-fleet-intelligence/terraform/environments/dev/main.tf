###############################################################################
# Week 4: Glue Fleet Intelligence Platform — dev environment
# ServiceNow ticket → SSM Data Sync → Glue ETL → Athena SQL over fleet
###############################################################################

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "~> 5.0" }
  }

  backend "s3" {
    bucket       = "jay-terraformstate-bucket"
    key          = "week-04-glue-fleet-intelligence/dev/terraform.tfstate"
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
  # Deterministic ARNs — breaks Lambda ↔ Step Functions circular dependency
  state_machine_arn         = "arn:aws:states:${var.aws_region}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.project_name}-fleet-pipeline-${var.environment}"
  lambda_glue_trigger_arn   = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-glue-trigger-${var.environment}"
  lambda_status_updater_arn = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:${var.project_name}-status-updater-${var.environment}"

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    Week        = "04"
    ManagedBy   = "Terraform"
    Owner       = "jay"
  }
}

# ── SNS Alert Topic ────────────────────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
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

# ── S3 Buckets + SSM Resource Data Sync ───────────────────────────────────────
module "s3" {
  source       = "../../modules/s3"
  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  account_id   = data.aws_caller_identity.current.account_id
  tags         = local.common_tags
}

# ── IAM Roles (Glue + Lambda + Step Functions) ────────────────────────────────
module "iam" {
  source       = "../../modules/iam"
  project_name = var.project_name
  environment  = var.environment

  raw_bucket_arn            = module.s3.raw_bucket_arn
  curated_bucket_arn        = module.s3.curated_bucket_arn
  state_machine_arn         = local.state_machine_arn
  lambda_glue_trigger_arn   = local.lambda_glue_trigger_arn
  lambda_status_updater_arn = local.lambda_status_updater_arn
  tags                      = local.common_tags

  depends_on = [module.s3]
}

# ── Glue (Catalog + Crawler + ETL Job + Athena Workgroup) ─────────────────────
module "glue" {
  source       = "../../modules/glue"
  project_name = var.project_name
  environment  = var.environment

  glue_role_arn              = module.iam.glue_role_arn
  raw_bucket_name            = module.s3.raw_bucket_name
  curated_bucket_name        = module.s3.curated_bucket_name
  athena_results_bucket_name = module.s3.athena_results_bucket_name
  tags                       = local.common_tags

  depends_on = [module.s3, module.iam]
}

# ── Step Functions ─────────────────────────────────────────────────────────────
module "step_functions" {
  source       = "../../modules/step-functions"
  project_name = var.project_name
  environment  = var.environment

  sfn_role_arn              = module.iam.step_functions_role_arn
  glue_trigger_lambda_arn   = local.lambda_glue_trigger_arn
  status_updater_lambda_arn = local.lambda_status_updater_arn
  crawler_name              = module.glue.crawler_name
  etl_job_name              = module.glue.etl_job_name
  tags                      = local.common_tags

  depends_on = [module.iam, module.glue]
}

# ── Lambda Functions ───────────────────────────────────────────────────────────
module "lambda" {
  source       = "../../modules/lambda"
  project_name = var.project_name
  environment  = var.environment

  lambda_role_arn        = module.iam.lambda_role_arn
  state_machine_arn      = local.state_machine_arn
  crawler_name           = module.glue.crawler_name
  etl_job_name           = module.glue.etl_job_name
  athena_workgroup_name  = module.glue.athena_workgroup_name

  hmac_secret_param   = aws_ssm_parameter.hmac_secret.name
  snow_instance_param = aws_ssm_parameter.snow_instance.name
  snow_user_param     = aws_ssm_parameter.snow_user.name
  snow_password_param = aws_ssm_parameter.snow_password.name

  tags = local.common_tags

  depends_on = [module.iam, module.glue, module.step_functions]
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
