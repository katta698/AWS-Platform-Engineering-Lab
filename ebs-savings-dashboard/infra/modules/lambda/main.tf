# ── Package the Lambda zip ────────────────────────────────────────────────────
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/src"
  output_path = "${path.module}/dist/handler.zip"
}

# ── DLQ ───────────────────────────────────────────────────────────────────────
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.prefix}-lambda-dlq"
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id         = var.kms_key_arn
}

# ── CloudWatch log group (pre-create so we control retention) ─────────────────
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.prefix}-ebs-savings"
  retention_in_days = 30
}

# ── Security group (only created when use_vpc = true) ─────────────────────────
resource "aws_security_group" "lambda" {
  count  = var.use_vpc ? 1 : 0
  name   = "${var.prefix}-lambda-sg"
  vpc_id = var.vpc_id

  egress {
    description = "HTTPS to AWS APIs"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ── IAM role ──────────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.prefix}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

# Basic execution (CloudWatch Logs) — use VPC variant when in a VPC
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = var.use_vpc ? "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole" : "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# X-Ray tracing
resource "aws_iam_role_policy_attachment" "xray" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

data "aws_iam_policy_document" "lambda_permissions" {
  # Athena — scoped to the specific workgroup
  statement {
    sid = "Athena"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StopQueryExecution",
    ]
    resources = [var.athena_workgroup_arn]
  }

  # Glue — read-only for Athena schema lookups
  statement {
    sid       = "Glue"
    actions   = ["glue:GetTable", "glue:GetDatabase", "glue:GetPartitions"]
    resources = ["*"]
  }

  # S3 CUR — read only
  statement {
    sid       = "S3CURRead"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [var.cur_bucket_arn, "${var.cur_bucket_arn}/*"]
  }

  # S3 Athena results — read + write
  statement {
    sid       = "S3ResultsWrite"
    actions   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject"]
    resources = ["${var.results_bucket_arn}/*"]
  }
  statement {
    sid       = "S3ResultsList"
    actions   = ["s3:ListBucket"]
    resources = [var.results_bucket_arn]
  }

  # KMS — only the keys this function touches
  statement {
    sid       = "KMS"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [var.cur_kms_key_arn, var.athena_kms_key_arn, var.kms_key_arn]
  }

  # EC2 — describe only, no mutations
  statement {
    sid       = "EC2Describe"
    actions   = ["ec2:DescribeVolumes", "ec2:DescribeInstances", "ec2:DescribeSnapshots"]
    resources = ["*"]
  }

  # STS — assume cross-account read role; constrained to org if org_id provided
  dynamic "statement" {
    for_each = var.org_id != "" ? [1] : []
    content {
      sid       = "STSCrossAccount"
      actions   = ["sts:AssumeRole"]
      resources = ["arn:aws:iam::*:role/EBSDashboardReadRole"]
      condition {
        test     = "StringEquals"
        variable = "aws:PrincipalOrgID"
        values   = [var.org_id]
      }
    }
  }

  # SQS DLQ
  statement {
    sid       = "SQS"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.dlq.arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "ebs-savings-permissions"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

# ── Lambda function ───────────────────────────────────────────────────────────
resource "aws_lambda_function" "ebs_savings" {
  function_name    = "${var.prefix}-ebs-savings"
  description      = "EBS Savings Dashboard API — runs Athena + EC2 DescribeVolumes"
  runtime          = "python3.12"
  handler          = "handler.main"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 60
  memory_size      = 512

  dynamic "vpc_config" {
    for_each = var.use_vpc ? [1] : []
    content {
      subnet_ids         = var.private_subnet_ids
      security_group_ids = [aws_security_group.lambda[0].id]
    }
  }

  environment {
    variables = {
      ATHENA_DATABASE  = var.athena_database
      ATHENA_WORKGROUP = var.athena_workgroup_name
      RESULTS_BUCKET   = var.results_bucket_name
      MEMBER_ROLE_NAME = "EBSDashboardReadRole"
      ORG_ID           = var.org_id
    }
  }

  kms_key_arn = var.kms_key_arn

  tracing_config { mode = "Active" }

  dead_letter_config { target_arn = aws_sqs_queue.dlq.arn }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.lambda_basic,
  ]
}
