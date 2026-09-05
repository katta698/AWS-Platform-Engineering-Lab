# ── Personal account test stack ───────────────────────────────────────────────
# Deploys only what's needed to test the full pipeline:
#   S3 (synthetic CUR data) → Glue → Athena → Lambda → API GW
# No CloudFront, no WAF, no KMS CMKs — keeps cost near zero.
# Run `terraform destroy` when done to clean up everything.

terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { Project = "ebs-dash-test", ManagedBy = "terraform" }
  }
}

variable "aws_region" { default = "us-east-1" }
variable "prefix" { default = "ebstest" }

data "aws_caller_identity" "current" {}

# ── S3 bucket — receives synthetic CUR Parquet files ─────────────────────────
resource "aws_s3_bucket" "cur" {
  bucket        = "${var.prefix}-cur-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # easy cleanup with terraform destroy
}

resource "aws_s3_bucket_public_access_block" "cur" {
  bucket                  = aws_s3_bucket.cur.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── S3 bucket — Athena query results ─────────────────────────────────────────
resource "aws_s3_bucket" "results" {
  bucket        = "${var.prefix}-athena-results-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "results" {
  bucket                  = aws_s3_bucket.results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "results" {
  bucket = aws_s3_bucket.results.id
  rule {
    id     = "expire"
    status = "Enabled"
    filter {}
    expiration { days = 3 }
  }
}

# ── Glue database + crawler ───────────────────────────────────────────────────
resource "aws_glue_catalog_database" "cur" {
  name = "cur_db"
}

data "aws_iam_policy_document" "glue_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue" {
  name               = "${var.prefix}-glue-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_s3" {
  role = aws_iam_role.glue.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.cur.arn, "${aws_s3_bucket.cur.arn}/*"]
    }]
  })
}

resource "aws_glue_crawler" "cur" {
  name          = "${var.prefix}-crawler"
  role          = aws_iam_role.glue.arn
  database_name = aws_glue_catalog_database.cur.name

  s3_target {
    path = "s3://${aws_s3_bucket.cur.bucket}/cur/synthetic-report/"
  }

  # No schedule for test — run manually via console or CLI
  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }
}

# ── Athena workgroup ──────────────────────────────────────────────────────────
resource "aws_athena_workgroup" "test" {
  name          = "${var.prefix}-workgroup"
  state         = "ENABLED"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false

    result_configuration {
      output_location = "s3://${aws_s3_bucket.results.bucket}/results/"
    }

    engine_version {
      selected_engine_version = "Athena engine version 3"
    }

    bytes_scanned_cutoff_per_query = 1073741824 # 1 GB limit for personal account
  }
}

# ── Lambda ────────────────────────────────────────────────────────────────────
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../modules/lambda/src/handler.py"
  output_path = "${path.module}/dist/handler.zip"
}

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

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "lambda" {
  role = aws_iam_role.lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Athena"
        Effect = "Allow"
        Action = ["athena:StartQueryExecution", "athena:GetQueryExecution",
        "athena:GetQueryResults", "athena:StopQueryExecution"]
        Resource = [aws_athena_workgroup.test.arn]
      },
      {
        Sid      = "Glue"
        Effect   = "Allow"
        Action   = ["glue:GetTable", "glue:GetDatabase", "glue:GetPartitions"]
        Resource = ["*"]
      },
      {
        Sid      = "S3CUR"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.cur.arn, "${aws_s3_bucket.cur.arn}/*"]
      },
      {
        Sid      = "S3Results"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:GetObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.results.arn, "${aws_s3_bucket.results.arn}/*"]
      },
      {
        Sid      = "EC2Describe"
        Effect   = "Allow"
        Action   = ["ec2:DescribeVolumes", "ec2:DescribeInstances", "ec2:DescribeSnapshots"]
        Resource = ["*"]
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.prefix}-ebs-savings"
  retention_in_days = 7
}

resource "aws_lambda_function" "ebs_savings" {
  function_name    = "${var.prefix}-ebs-savings"
  runtime          = "python3.12"
  handler          = "handler.main"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 60
  memory_size      = 512

  environment {
    variables = {
      ATHENA_DATABASE  = aws_glue_catalog_database.cur.name
      ATHENA_WORKGROUP = aws_athena_workgroup.test.name
      RESULTS_BUCKET   = aws_s3_bucket.results.bucket
      # Glue crawler derives the table name from the S3 path segment after cur/
      # e.g. cur/synthetic-report/ → table "synthetic_report"
      CUR_TABLE = "synthetic_report"
      # Phase 1: leave these empty — no cross-account EC2 calls
      MEMBER_ROLE_NAME = ""
      ORG_ID           = ""
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# ── API Gateway (no auth for local testing) ───────────────────────────────────
resource "aws_apigatewayv2_api" "test" {
  name          = "${var.prefix}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["Content-Type"]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.test.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ebs_savings.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "ebs_savings" {
  api_id    = aws_apigatewayv2_api.test.id
  route_key = "GET /ebs-savings"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "test" {
  api_id      = aws_apigatewayv2_api.test.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ebs_savings.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.test.execution_arn}/*/*"
}

# ── Outputs ───────────────────────────────────────────────────────────────────
output "cur_bucket" {
  value = aws_s3_bucket.cur.bucket
}
output "api_url" {
  value = aws_apigatewayv2_stage.test.invoke_url
}
output "crawler_name" {
  value = aws_glue_crawler.cur.name
}
output "next_steps" {
  value = <<-EOT

    ── Next steps ──────────────────────────────────────────────────
    1. Generate + upload synthetic data:
       cd ../test
       pip install pyarrow pandas boto3
       python generate_mock_cur.py --upload --bucket ${aws_s3_bucket.cur.bucket}

    2. Run the Glue crawler:
       aws glue start-crawler --name ${aws_glue_crawler.cur.name}
       aws glue get-crawler --name ${aws_glue_crawler.cur.name} --query 'Crawler.State'

    3. Set API URL in frontend:
       echo "VITE_USE_MOCK=false" > ../../.env.local
       echo "VITE_API_URL=${aws_apigatewayv2_stage.test.invoke_url}" >> ../../.env.local

    4. Run the dashboard:
       cd ../../ && npm run dev

    5. Clean up when done:
       terraform destroy
    ────────────────────────────────────────────────────────────────
  EOT
}
