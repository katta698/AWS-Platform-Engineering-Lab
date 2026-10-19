terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

# ── S3 bucket ─────────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "cur" {
  bucket = "${var.prefix}-cur-reports"
}

resource "aws_s3_bucket_public_access_block" "cur" {
  bucket                  = aws_s3_bucket.cur.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "cur" {
  bucket = aws_s3_bucket.cur.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cur" {
  bucket = aws_s3_bucket.cur.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true # cuts KMS API cost ~99%
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cur" {
  bucket = aws_s3_bucket.cur.id
  rule {
    id     = "cur-tiering"
    status = "Enabled"
    filter { prefix = "cur/" }
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 365
      storage_class = "GLACIER_IR"
    }
    noncurrent_version_expiration { noncurrent_days = 90 }
  }
}

resource "aws_s3_bucket_logging" "cur" {
  bucket        = aws_s3_bucket.cur.id
  target_bucket = aws_s3_bucket.cur.id # log to same bucket; use separate logging bucket in prod
  target_prefix = "s3-access-logs/"
}

# ── Bucket policy ─────────────────────────────────────────────────────────────
data "aws_iam_policy_document" "cur_bucket" {
  # Allow AWS Billing to write CUR files
  statement {
    sid = "AllowBillingWrite"
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl", "s3:GetBucketPolicy", "s3:PutObject"]
    resources = [aws_s3_bucket.cur.arn, "${aws_s3_bucket.cur.arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.management_account_id]
    }
  }

  # Deny all non-SSL traffic
  statement {
    sid    = "DenyNonSSL"
    effect = "Deny"
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.cur.arn, "${aws_s3_bucket.cur.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "cur" {
  bucket = aws_s3_bucket.cur.id
  policy = data.aws_iam_policy_document.cur_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.cur]
}

# ── CUR report definition (must use us-east-1 provider) ───────────────────────
resource "aws_cur_report_definition" "ebs" {
  provider = aws.us_east_1

  report_name                = "${var.prefix}-cur"
  time_unit                  = "HOURLY"
  format                     = "Parquet"
  compression                = "Parquet"
  report_versioning          = "OVERWRITE_REPORT"
  refresh_closed_reports     = true
  additional_schema_elements = ["RESOURCES"]

  s3_bucket = aws_s3_bucket.cur.bucket
  s3_prefix = "cur"
  s3_region = var.region
}
