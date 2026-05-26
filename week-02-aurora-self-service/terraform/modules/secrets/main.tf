###############################################################################
# Secrets Manager — Master credential + rotation Lambda
# Per-tenant secrets are created dynamically by the db_provisioner Lambda.
###############################################################################

locals {
  name        = "${var.project}-${var.environment}"
  common_tags = merge(var.tags, { Module = "secrets" })
}

# ── Master Secret ─────────────────────────────────────────────────────────────
# Stores Aurora admin credentials in the format Secrets Manager rotation expects
resource "aws_secretsmanager_secret" "master" {
  name        = "/${var.project}/${var.environment}/aurora/master"
  description = "Aurora master credentials for ${local.name}"

  recovery_window_in_days = 0 # Instant delete for lab teardown

  tags = merge(local.common_tags, { SecretType = "master" })
}

resource "aws_secretsmanager_secret_version" "master" {
  secret_id = aws_secretsmanager_secret.master.id
  secret_string = jsonencode({
    engine   = "postgres"
    host     = var.cluster_endpoint
    port     = var.cluster_port
    dbname   = var.database_name
    username = var.master_username
    password = var.master_password
  })
}

# ── Rotation Lambda IAM Role ──────────────────────────────────────────────────
resource "aws_iam_role" "rotation_lambda" {
  name = "${local.name}-secret-rotation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rotation_basic" {
  role       = aws_iam_role.rotation_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "rotation_secrets" {
  name = "${local.name}-rotation-secrets-policy"
  role = aws_iam_role.rotation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:UpdateSecretVersionStage"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:/${var.project}/${var.environment}/*"
      },
      {
        Effect   = "Allow"
        Action   = "secretsmanager:GetRandomPassword"
        Resource = "*"
      }
    ]
  })
}

# ── Rotation Lambda Function ──────────────────────────────────────────────────
# Uses our custom rotation function (lambda/secret_rotation/index.py)
data "archive_file" "rotation" {
  type        = "zip"
  source_file = "${path.module}/../../../lambda/secret_rotation/index.py"
  output_path = "${path.module}/../../../lambda/secret_rotation/secret_rotation.zip"
}

resource "aws_lambda_function" "rotation" {
  function_name    = "${local.name}-secret-rotation"
  filename         = data.archive_file.rotation.output_path
  source_code_hash = data.archive_file.rotation.output_base64sha256
  role             = aws_iam_role.rotation_lambda.arn
  handler          = "index.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30

  vpc_config {
    subnet_ids         = var.lambda_subnet_ids
    security_group_ids = [var.lambda_security_group_id]
  }

  environment {
    variables = {
      SECRETS_MANAGER_ENDPOINT = "https://secretsmanager.${data.aws_region.current.name}.amazonaws.com"
    }
  }

  tags = local.common_tags
}

data "aws_region" "current" {}

# Allow Secrets Manager to invoke the rotation Lambda
resource "aws_lambda_permission" "secrets_manager" {
  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
}

# ── Enable Rotation on Master Secret ─────────────────────────────────────────
resource "aws_secretsmanager_secret_rotation" "master" {
  secret_id           = aws_secretsmanager_secret.master.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn

  rotation_rules {
    automatically_after_days = var.rotation_days
  }

  depends_on = [aws_lambda_permission.secrets_manager]
}
