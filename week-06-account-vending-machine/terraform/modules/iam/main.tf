###############################################################################
# IAM Roles — webhook_receiver, account_creator, account_mover, status_notifier,
# Step Functions. Must be deployed in the Organizations MANAGEMENT account —
# organizations:CreateAccount/MoveAccount only work there.
###############################################################################

# ── webhook_receiver role ──────────────────────────────────────────────────────
resource "aws_iam_role" "webhook_receiver" {
  name = "${var.project_name}-webhook-receiver-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "webhook_receiver_basic" {
  role       = aws_iam_role.webhook_receiver.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "webhook_receiver_permissions" {
  name = "${var.project_name}-webhook-receiver-permissions-${var.environment}"
  role = aws_iam_role.webhook_receiver.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "StartStepFunctions"
        Effect   = "Allow"
        Action   = ["states:StartExecution"]
        Resource = [var.state_machine_arn]
      },
      {
        Sid      = "SSMParameterRead"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:*:*:parameter/${var.project_name}/${var.environment}/*"
      },
    ]
  })
}

# ── account_creator role (organizations:CreateAccount) ────────────────────────
resource "aws_iam_role" "account_creator" {
  name = "${var.project_name}-account-creator-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "account_creator_basic" {
  role       = aws_iam_role.account_creator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "account_creator_permissions" {
  name = "${var.project_name}-account-creator-permissions-${var.environment}"
  role = aws_iam_role.account_creator.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "OrganizationsCreateAccount"
        Effect   = "Allow"
        Action   = ["organizations:CreateAccount", "organizations:DescribeCreateAccountStatus"]
        Resource = "*"
      },
    ]
  })
}

# ── account_mover role (organizations:MoveAccount + tag) ──────────────────────
resource "aws_iam_role" "account_mover" {
  name = "${var.project_name}-account-mover-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "account_mover_basic" {
  role       = aws_iam_role.account_mover.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "account_mover_permissions" {
  name = "${var.project_name}-account-mover-permissions-${var.environment}"
  role = aws_iam_role.account_mover.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "OrganizationsMoveAndTag"
        Effect   = "Allow"
        Action   = ["organizations:MoveAccount", "organizations:TagResource"]
        Resource = "*"
      },
    ]
  })
}

# ── status_notifier role (SSM read for ServiceNow creds) ──────────────────────
resource "aws_iam_role" "status_notifier" {
  name = "${var.project_name}-status-notifier-role-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "status_notifier_basic" {
  role       = aws_iam_role.status_notifier.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "status_notifier_permissions" {
  name = "${var.project_name}-status-notifier-permissions-${var.environment}"
  role = aws_iam_role.status_notifier.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "SSMParameterRead"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:*:*:parameter/${var.project_name}/${var.environment}/*"
      },
    ]
  })
}

# ── Step Functions execution role ──────────────────────────────────────────────
resource "aws_iam_role" "step_functions" {
  name = "${var.project_name}-sfn-role-${var.environment}"

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

resource "aws_iam_role_policy" "sfn_policy" {
  name = "${var.project_name}-sfn-policy-${var.environment}"
  role = aws_iam_role.step_functions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = [for arn in var.lambda_arns : arn]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery", "logs:GetLogDelivery",
          "logs:UpdateLogDelivery", "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries", "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies", "logs:DescribeLogGroups",
        ]
        Resource = "*"
      }
    ]
  })
}
