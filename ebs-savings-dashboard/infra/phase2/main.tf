# ── Phase 2: CUR + cross-account EC2 inventory ────────────────────────────────
#
# Extends Phase 1 with live Volume Inventory data from every member account.
#
# Deploys:  S3 → Glue → Athena → Lambda (Phase 2) → API Gateway
# Handler:  handler_phase2.py — assumes EBSDashboardReadRole in each member account
# Tabs:     All 5 tabs including Volume Inventory
#
# Prerequisites before terraform apply here:
#   1. Phase 1 is already deployed (infra/phase1/) and validated
#   2. EBSDashboardReadRole exists in every member account:
#        cd ../cross_account_roles
#        aws organizations list-accounts \
#          --query 'Accounts[?Status==`ACTIVE`].Id' \
#          --output text | tr '\t' '\n' > accounts.txt
#        python generate_providers.py \
#          --accounts accounts.txt \
#          --lambda-role <this Lambda role ARN from outputs below> \
#          --org-id <your-org-id>
#        terraform init && terraform apply
#
# This stack is INDEPENDENT of infra/phase1/ — both can run simultaneously.
# Phase 2 creates its own S3 buckets, Glue DB, Athena workgroup, Lambda, and API GW.
#
# Usage:
#   cd infra/phase2
#   mkdir dist
#   terraform init
#   terraform apply

terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
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
    tags = {
      Project   = "ebs-dash-phase2"
      ManagedBy = "terraform"
      Phase     = "2"
    }
  }
}

variable "aws_region" { default = "us-east-1" }
variable "prefix" { default = "ebsp2" }

# Required for Phase 2 — the name of the IAM role that exists in every member account.
# Must match what generate_providers.py created (default: EBSDashboardReadRole).
variable "member_role_name" {
  description = "IAM role name in each member account that Lambda assumes for EC2 inventory"
  default     = "EBSDashboardReadRole"
}

# Optional — adds aws:PrincipalOrgID condition to trust policies for defence-in-depth.
# Find with: aws organizations describe-organization --query 'Organization.Id' --output text
variable "org_id" {
  description = "AWS Organizations ID (e.g. o-ab1cd2ef34). Leave empty to skip org condition."
  default     = ""
}

data "aws_caller_identity" "current" {}

# ── S3: synthetic CUR Parquet files ───────────────────────────────────────────
resource "aws_s3_bucket" "cur" {
  bucket        = "${var.prefix}-cur-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "cur" {
  bucket                  = aws_s3_bucket.cur.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── S3: Athena query results ───────────────────────────────────────────────────
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

# ── Glue: database + crawler ───────────────────────────────────────────────────
resource "aws_glue_catalog_database" "cur" {
  name = "${var.prefix}_cur_db"
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

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }
}

# ── Athena workgroup ───────────────────────────────────────────────────────────
resource "aws_athena_workgroup" "phase2" {
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

    bytes_scanned_cutoff_per_query = 1073741824
  }
}

# ── Lambda ─────────────────────────────────────────────────────────────────────
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../modules/lambda/src/handler_phase2.py"
  output_path = "${path.module}/dist/handler_phase2.zip"
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
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution"
        ]
        Resource = [aws_athena_workgroup.phase2.arn]
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
        Action   = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [aws_s3_bucket.cur.arn, "${aws_s3_bucket.cur.arn}/*"]
      },
      {
        Sid    = "S3Results"
        Effect = "Allow"
        Action = [
          "s3:PutObject", "s3:GetObject", "s3:DeleteObject",
          "s3:ListBucket", "s3:GetBucketLocation",
          "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts"
        ]
        Resource = [aws_s3_bucket.results.arn, "${aws_s3_bucket.results.arn}/*"]
      },
      {
        # Assume EBSDashboardReadRole in every member account for EC2 inventory
        Sid      = "AssumeEBSReadRole"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = ["arn:aws:iam::*:role/${var.member_role_name}"]
      },
      {
        # List member accounts to iterate across the org
        Sid      = "OrgListAccounts"
        Effect   = "Allow"
        Action   = ["organizations:ListAccounts"]
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
  handler          = "handler_phase2.main"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 60
  memory_size      = 512

  environment {
    variables = {
      ATHENA_DATABASE  = aws_glue_catalog_database.cur.name
      ATHENA_WORKGROUP = aws_athena_workgroup.phase2.name
      RESULTS_BUCKET   = aws_s3_bucket.results.bucket
      CUR_TABLE        = "synthetic_report"
      MEMBER_ROLE_NAME = var.member_role_name
      ORG_ID           = var.org_id
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# ── API Gateway ────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_api" "phase2" {
  name          = "${var.prefix}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["Content-Type"]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.phase2.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ebs_savings.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "ebs_savings" {
  api_id    = aws_apigatewayv2_api.phase2.id
  route_key = "GET /ebs-savings"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "phase2" {
  api_id      = aws_apigatewayv2_api.phase2.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ebs_savings.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.phase2.execution_arn}/*/*"
}

# ── Outputs ────────────────────────────────────────────────────────────────────
output "cur_bucket" { value = aws_s3_bucket.cur.bucket }
output "api_url" { value = aws_apigatewayv2_stage.phase2.invoke_url }
output "crawler_name" { value = aws_glue_crawler.cur.name }
output "lambda_name" { value = aws_lambda_function.ebs_savings.function_name }
output "lambda_role_arn" {
  description = "Pass this ARN to generate_providers.py --lambda-role"
  value       = aws_iam_role.lambda.arn
}

output "next_steps" {
  value = <<-EOT

    ── Phase 2 — Next steps ──────────────────────────────────────────────────────
    1. Generate + upload synthetic CUR data (skip if already done for Phase 1):
       cd ../../test
       python generate_mock_cur.py --upload --bucket ${aws_s3_bucket.cur.bucket}

    2. Run the Glue crawler:
       aws glue start-crawler --name ${aws_glue_crawler.cur.name}
       aws glue get-crawler --name ${aws_glue_crawler.cur.name} --query 'Crawler.State'

    3. Deploy EBSDashboardReadRole to every member account (if not done yet):
       cd ../cross_account_roles
       aws organizations list-accounts \
         --query 'Accounts[?Status==`ACTIVE`].Id' \
         --output text | tr '\t' '\n' > accounts.txt
       python generate_providers.py \
         --accounts accounts.txt \
         --lambda-role ${aws_iam_role.lambda.arn} \
         --org-id <your-org-id>
       terraform init && terraform apply

    4. Wire up the frontend to Phase 2 API:
       echo "VITE_USE_MOCK=false"  > ../../../../.env.local
       echo "VITE_API_URL=${aws_apigatewayv2_stage.phase2.invoke_url}" >> ../../../../.env.local

    5. Run the dashboard:
       cd ../../../../ && npm run dev

    6. Cleanup (Phase 2 only — does NOT touch Phase 1):
       terraform destroy
    ─────────────────────────────────────────────────────────────────────────────
  EOT
}
