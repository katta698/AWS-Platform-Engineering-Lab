###############################################################################
# Lambda Module — Week 3 SSM Fleet Management
###############################################################################

data "aws_region" "current" {}

locals {
  functions = {
    webhook_receiver = {
      description = "Validates ServiceNow webhook, routes to Step Functions"
      timeout     = 30
      memory      = 256
      env = {
        STATE_MACHINE_ARN        = var.state_machine_arn
        WEBHOOK_SECRET           = var.webhook_secret
        SSM_AUTOMATION_ROLE_PARAM = "/${var.project}/${var.environment}/ssm/automation-role-arn"
      }
    }
    fleet_onboarder = {
      description = "Runs SSM Automation to onboard EC2 instance into managed fleet"
      timeout     = 360
      memory      = 256
      env = {
        ONBOARD_DOCUMENT_NAME = var.onboard_document_name
      }
    }
    patch_orchestrator = {
      description = "Triggers SSM patch run across fleet, returns compliance summary"
      timeout     = 720
      memory      = 256
      env = {
        PATCH_FLEET_DOCUMENT_NAME = var.patch_fleet_document_name
      }
    }
    status_updater = {
      description = "Closes ServiceNow ticket with fleet operation results"
      timeout     = 60
      memory      = 256
      env = {
        SNOW_INSTANCE_URL_PARAM = "/${var.project}/${var.environment}/servicenow/instance-url"
        SNOW_USERNAME_PARAM     = "/${var.project}/${var.environment}/servicenow/username"
        SNOW_PASSWORD_PARAM     = "/${var.project}/${var.environment}/servicenow/password"
      }
    }
  }
}

data "archive_file" "lambda" {
  for_each    = local.functions
  type        = "zip"
  source_file = "${path.module}/../../../lambda/${each.key}/handler.py"
  output_path = "${path.module}/../../../lambda/${each.key}/function.zip"
}

resource "aws_lambda_function" "this" {
  for_each = local.functions

  function_name = "${var.project}-${var.environment}-${replace(each.key, "_", "-")}"
  description   = each.value.description
  role          = var.lambda_role_arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = each.value.timeout
  memory_size   = each.value.memory

  filename         = data.archive_file.lambda[each.key].output_path
  source_code_hash = data.archive_file.lambda[each.key].output_base64sha256

  environment {
    variables = each.value.env
  }

  tags = { Name = "${var.project}-${var.environment}-${each.key}" }
}

resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = local.functions
  name              = "/aws/lambda/${var.project}-${var.environment}-${replace(each.key, "_", "-")}"
  retention_in_days = 14
}

# SSM Parameter Store — ServiceNow credentials + SSM automation role
resource "aws_ssm_parameter" "snow_instance_url" {
  name  = "/${var.project}/${var.environment}/servicenow/instance-url"
  type  = "SecureString"
  value = var.servicenow_instance_url
}

resource "aws_ssm_parameter" "snow_username" {
  name  = "/${var.project}/${var.environment}/servicenow/username"
  type  = "SecureString"
  value = var.servicenow_username
}

resource "aws_ssm_parameter" "snow_password" {
  name  = "/${var.project}/${var.environment}/servicenow/password"
  type  = "SecureString"
  value = var.servicenow_password
}

resource "aws_ssm_parameter" "automation_role_arn" {
  name  = "/${var.project}/${var.environment}/ssm/automation-role-arn"
  type  = "String"
  value = var.ssm_automation_role_arn
}
