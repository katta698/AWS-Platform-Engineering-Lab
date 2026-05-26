###############################################################################
# Step Functions — Database Provisioning Workflow
# Flow: ProvisionDatabase → UpdateServiceNow → Done
###############################################################################

locals {
  name        = "${var.project}-${var.environment}"
  common_tags = merge(var.tags, { Module = "step-functions" })
}

resource "aws_iam_role" "sfn" {
  name = "${local.name}-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "states.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "sfn_permissions" {
  name = "${local.name}-sfn-permissions"
  role = aws_iam_role.sfn.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "lambda:InvokeFunction"
        Resource = [
          var.db_provisioner_arn,
          var.status_updater_arn,
        ]
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogDelivery", "logs:GetLogDelivery",
                    "logs:UpdateLogDelivery", "logs:DeleteLogDelivery",
                    "logs:ListLogDeliveries", "logs:PutResourcePolicy",
                    "logs:DescribeResourcePolicies", "logs:DescribeLogGroups"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = var.alert_sns_topic_arn
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "sfn" {
  name              = "/aws/states/${local.name}-db-provisioning"
  retention_in_days = 30
  lifecycle { ignore_changes = [retention_in_days] }
  tags = local.common_tags
}

resource "aws_sfn_state_machine" "db_provisioning" {
  name     = "${local.name}-db-provisioning"
  role_arn = aws_iam_role.sfn.arn

  definition = jsonencode({
    Comment = "Aurora self-service database provisioning workflow"
    StartAt = "ProvisionDatabase"
    States = {
      ProvisionDatabase = {
        Type     = "Task"
        Resource = var.db_provisioner_arn
        Parameters = {
          "ticket_id.$"       = "$.ticket_id"
          "db_name.$"         = "$.db_name"
          "team.$"            = "$.team"
          "requested_by.$"    = "$.requested_by"
          "task_token.$"      = "$.task_token"
          "reader_endpoint"   = var.cluster_reader_endpoint
        }
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException"]
            IntervalSeconds = 5
            MaxAttempts     = 3
            BackoffRate     = 2
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "ProvisionFailed"
            ResultPath  = "$.error"
          }
        ]
        Next = "UpdateServiceNow"
      }

      UpdateServiceNow = {
        Type     = "Task"
        Resource = var.status_updater_arn
        Retry = [
          {
            ErrorEquals     = ["Lambda.ServiceException"]
            IntervalSeconds = 10
            MaxAttempts     = 3
            BackoffRate     = 2
          }
        ]
        Catch = [
          {
            ErrorEquals = ["States.ALL"]
            Next        = "Done"  # DB is provisioned — ServiceNow failure is non-fatal
            ResultPath  = "$.servicenow_error"
          }
        ]
        Next = "Done"
      }

      Done = {
        Type = "Succeed"
      }

      ProvisionFailed = {
        Type  = "Fail"
        Error = "DatabaseProvisioningFailed"
        Cause = "Database provisioning Lambda returned an error — see CloudWatch logs"
      }
    }
  })

  logging_configuration {
    log_destination        = "${aws_cloudwatch_log_group.sfn.arn}:*"
    include_execution_data = true
    level                  = "ERROR"
  }

  tags = merge(local.common_tags, { Name = "${local.name}-db-provisioning" })
}
