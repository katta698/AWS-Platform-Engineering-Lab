# ── Phase 1: CUR-only test stack ──────────────────────────────────────────────
#
# Deploys:  S3 (synthetic CUR data) → Glue → Athena → Lambda → API Gateway
# Handler:  handler_phase1.py — no cross-account EC2 calls
# Tabs:     Overview, By Account, By Region, By Volume Type
# NOT deployed: CloudFront, WAF, KMS CMKs, cross-account IAM roles
#
# After Phase 1 is deployed and validated, deploy Phase 2 from infra/phase2/
# WITHOUT touching or destroying this stack.
#
# Usage:
#   cd infra/phase1
#   mkdir dist        (first time only — stores the Lambda zip)
#   terraform init
#   terraform apply
#   terraform destroy (cleanup when done)

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
      Project   = "ebs-savings-dashboard"
      ManagedBy = "terraform"
      Phase     = "1"
    }
  }
}

variable "aws_region" { default = "us-east-1" }
variable "prefix" { default = "ebsp1" }

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
    # Path determines Glue table name: cur/synthetic-report/ → table "synthetic_report"
    # Must match the path used by generate_mock_cur.py --upload
    path = "s3://${aws_s3_bucket.cur.bucket}/cur/synthetic-report/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }
}

# ── Athena workgroup ───────────────────────────────────────────────────────────
resource "aws_athena_workgroup" "phase1" {
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

    bytes_scanned_cutoff_per_query = 1073741824 # 1 GB guard for personal account
  }
}

# ── Lambda ─────────────────────────────────────────────────────────────────────
data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${path.module}/../modules/lambda/src/handler_phase1.py"
  output_path = "${path.module}/dist/handler_phase1.zip"
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
        Resource = [aws_athena_workgroup.phase1.arn]
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
      }
      # No EC2, no STS, no Organizations — Phase 1 is CUR-only
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
  handler          = "handler_phase1.main"
  role             = aws_iam_role.lambda.arn
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 60
  memory_size      = 512

  environment {
    variables = {
      ATHENA_DATABASE  = aws_glue_catalog_database.cur.name
      ATHENA_WORKGROUP = aws_athena_workgroup.phase1.name
      RESULTS_BUCKET   = aws_s3_bucket.results.bucket
      # Glue table name = S3 path segment after cur/ with hyphens → underscores
      # "synthetic-report" → "synthetic_report"
      CUR_TABLE = "synthetic_report"
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

# ── API Gateway (no auth — test only) ─────────────────────────────────────────
resource "aws_apigatewayv2_api" "phase1" {
  name          = "${var.prefix}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["Content-Type"]
  }
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.phase1.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ebs_savings.arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "ebs_savings" {
  api_id    = aws_apigatewayv2_api.phase1.id
  route_key = "GET /ebs-savings"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "phase1" {
  api_id      = aws_apigatewayv2_api.phase1.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ebs_savings.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.phase1.execution_arn}/*/*"
}

# ── S3: React frontend files ───────────────────────────────────────────────────
resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.prefix}-frontend-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "frontend" {
  bucket                  = aws_s3_bucket.frontend.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "frontend" {
  bucket = aws_s3_bucket.frontend.id
  versioning_configuration { status = "Enabled" }
}

# ── CloudFront Origin Access Control ──────────────────────────────────────────
resource "aws_cloudfront_origin_access_control" "frontend" {
  name                              = "${var.prefix}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Allow CloudFront OAC to read S3 bucket
data "aws_iam_policy_document" "frontend_s3" {
  statement {
    sid       = "AllowCloudFrontOAC"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]
    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudfront_distribution.frontend.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend" {
  bucket     = aws_s3_bucket.frontend.id
  policy     = data.aws_iam_policy_document.frontend_s3.json
  depends_on = [aws_s3_bucket_public_access_block.frontend]
}

# ── CloudFront distribution ────────────────────────────────────────────────────
resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # US + EU only — cheapest option

  # S3 origin — serves the React SPA
  origin {
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_id                = "s3-frontend"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  # Default — serve from S3
  default_cache_behavior {
    target_origin_id       = "s3-frontend"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    min_ttl     = 0
    default_ttl = 86400
    max_ttl     = 31536000
  }

  # SPA routing — return index.html for unknown paths (React Router)
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }
  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 0
  }

  viewer_certificate {
    cloudfront_default_certificate = true # free *.cloudfront.net cert
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }
}

# ── Outputs ────────────────────────────────────────────────────────────────────
output "cur_bucket" { value = aws_s3_bucket.cur.bucket }
output "api_url" { value = aws_apigatewayv2_stage.phase1.invoke_url }
output "crawler_name" { value = aws_glue_crawler.cur.name }
output "lambda_name" { value = aws_lambda_function.ebs_savings.function_name }
output "frontend_bucket" { value = aws_s3_bucket.frontend.bucket }
output "cloudfront_url" { value = "https://${aws_cloudfront_distribution.frontend.domain_name}" }

output "next_steps" {
  value = <<-EOT

    ── Phase 1 — Next steps ──────────────────────────────────────────────────────
    1. Generate + upload synthetic CUR data:
       cd infra/test
       pip install pyarrow pandas boto3
       python generate_mock_cur.py --upload --bucket ${aws_s3_bucket.cur.bucket}

    2. Run the Glue crawler (takes ~1 min):
       aws glue start-crawler --name ${aws_glue_crawler.cur.name} --profile personal
       aws glue get-crawler --name ${aws_glue_crawler.cur.name} --query 'Crawler.State' --profile personal
       (wait until State = "READY")

    3. Build + deploy frontend to CloudFront (permanent URL, no laptop needed):
       cd <repo-root>
       echo "VITE_USE_MOCK=false"               >  .env.production
       echo "VITE_API_URL=${aws_apigatewayv2_stage.phase1.invoke_url}" >> .env.production
       npm run build
       aws s3 sync dist/ s3://${aws_s3_bucket.frontend.bucket}/ --delete --profile personal
       aws cloudfront create-invalidation \
         --distribution-id ${aws_cloudfront_distribution.frontend.id} \
         --paths "/*" --profile personal

    4. Access dashboard (permanent, no laptop needed):
       https://${aws_cloudfront_distribution.frontend.domain_name}

    5. Local development (optional):
       echo "VITE_USE_MOCK=false"               >  .env.local
       echo "VITE_API_URL=${aws_apigatewayv2_stage.phase1.invoke_url}" >> .env.local
       npm run dev
       open http://localhost:3000

    6. When Phase 1 is validated, deploy Phase 2 WITHOUT destroying this:
       cd infra/phase2
       terraform init && terraform apply

    7. Cleanup Phase 1 only (does NOT affect Phase 2):
       cd infra/phase1
       terraform destroy
    ─────────────────────────────────────────────────────────────────────────────
  EOT
}
