###############################################################################
# IAM Module — Week 3 SSM Fleet Management
# Roles: EC2 instance role, SSM Automation role, Maintenance Window role,
#        Lambda execution role, Step Functions role
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ── EC2 Instance Role ─────────────────────────────────────────────────────────
resource "aws_iam_role" "ec2" {
  name = "${var.project}-${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "cloudwatch_agent" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy" "ec2_s3_logs" {
  name = "${var.project}-${var.environment}-ec2-s3-logs"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:PutObject", "s3:GetObject", "s3:GetEncryptionConfiguration"]
      Resource = ["${var.session_logs_bucket_arn}/*"]
    }]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project}-${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ── SSM Automation Role ───────────────────────────────────────────────────────
resource "aws_iam_role" "ssm_automation" {
  name = "${var.project}-${var.environment}-ssm-automation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ssm_automation" {
  name = "${var.project}-${var.environment}-ssm-automation-policy"
  role = aws_iam_role.ssm_automation.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMAutomation"
        Effect = "Allow"
        Action = [
          "ssm:SendCommand", "ssm:GetCommandInvocation",
          "ssm:ListCommandInvocations", "ssm:DescribeInstanceInformation",
          "ssm:DescribeInstancePatchStates", "ssm:DescribeInstancePatchStatesForPatchGroup",
          "ssm:ListComplianceSummaries", "ssm:GetPatchBaseline"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2Tagging"
        Effect = "Allow"
        Action = ["ec2:CreateTags", "ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Sid    = "S3Logs"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetObject"]
        Resource = ["${var.session_logs_bucket_arn}/*"]
      }
    ]
  })
}

# ── Maintenance Window Role ───────────────────────────────────────────────────
resource "aws_iam_role" "maintenance_window" {
  name = "${var.project}-${var.environment}-maintenance-window-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ssm.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "maintenance_window" {
  role       = aws_iam_role.maintenance_window.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonSSMMaintenanceWindowRole"
}

resource "aws_iam_role_policy" "maintenance_window_passrole" {
  name = "${var.project}-${var.environment}-mw-passrole"
  role = aws_iam_role.maintenance_window.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "iam:PassRole"
      Resource = aws_iam_role.maintenance_window.arn
    }]
  })
}

# ── Lambda Execution Role ─────────────────────────────────────────────────────
resource "aws_iam_role" "lambda" {
  name = "${var.project}-${var.environment}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda_ssm" {
  name = "${var.project}-${var.environment}-lambda-ssm-policy"
  role = aws_iam_role.lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMAccess"
        Effect = "Allow"
        Action = [
          "ssm:StartAutomationExecution", "ssm:GetAutomationExecution",
          "ssm:SendCommand", "ssm:GetCommandInvocation",
          "ssm:DescribeInstanceInformation", "ssm:DescribeInstancePatchStates",
          "ssm:DescribeInstancePatchStatesForPatchGroup",
          "ssm:ListComplianceSummaries", "ssm:ListResourceComplianceSummaries",
          "ssm:GetParameter", "ssm:GetParameters"
        ]
        Resource = "*"
      },
      {
        Sid    = "StepFunctions"
        Effect = "Allow"
        Action = ["states:StartExecution"]
        Resource = "arn:aws:states:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:stateMachine:${var.project}-${var.environment}-*"
      },
      {
        Sid    = "IAMPassRole"
        Effect = "Allow"
        Action = "iam:PassRole"
        Resource = aws_iam_role.ssm_automation.arn
      }
    ]
  })
}

# ── Step Functions Role ───────────────────────────────────────────────────────
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
}

resource "aws_iam_role_policy" "step_functions" {
  name = "${var.project}-${var.environment}-sfn-policy"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "InvokeLambda"
        Effect = "Allow"
        Action = "lambda:InvokeFunction"
        Resource = "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:${var.project}-${var.environment}-*"
      },
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutLogEvents",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}
