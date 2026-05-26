###############################################################################
# Module: Step Functions State Machine
# Orchestrates: Validate → UpdateTicket → TriggerDeployment → Notify
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── IAM Role for Step Functions to invoke Lambda ──────────────────────────────
resource "aws_iam_role" "step_functions" {
  name = "${var.project}-${var.environment}-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "states.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "step_functions" {
  name = "sfn-invoke-lambda"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeLambdas"
        Effect = "Allow"
        Action = ["lambda:InvokeFunction"]
        Resource = [
          var.status_updater_arn,
          var.deployment_trigger_arn,
          "${var.status_updater_arn}:*",
          "${var.deployment_trigger_arn}:*"
        ]
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

# ── State Machine ─────────────────────────────────────────────────────────────
resource "aws_sfn_state_machine" "main" {
  name     = "${var.project}-${var.environment}-provisioning"
  role_arn = aws_iam_role.step_functions.arn

  # Inject real Lambda ARNs into the state machine definition
  definition = templatefile("${path.root}/../../../step_functions/state_machine.json", {
    ValidateLambdaArn        = var.status_updater_arn   # reuse status_updater for validation
    StatusUpdaterLambdaArn   = var.status_updater_arn
    DeploymentTriggerLambdaArn = var.deployment_trigger_arn
  })

  tags = var.tags
}
