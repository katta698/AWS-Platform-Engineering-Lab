###############################################################################
# S3 Buckets — raw (SSM sync) + curated (Parquet) + athena results
# SSM Resource Data Sync is configured here (writes to raw bucket)
###############################################################################

# ── Raw bucket (SSM Resource Data Sync writes here) ───────────────────────────
resource "aws_s3_bucket" "raw" {
  bucket        = "${var.project_name}-raw-${var.environment}"
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_versioning" "raw" {
  bucket = aws_s3_bucket.raw.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket                  = aws_s3_bucket.raw.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id
  rule {
    id     = "expire-raw-90-days"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = 90 }
  }
}

# ── SSM bucket policy — required for Resource Data Sync to write ──────────────
resource "aws_s3_bucket_policy" "raw_ssm" {
  bucket = aws_s3_bucket.raw.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SSMBucketPermissionsCheck"
        Effect = "Allow"
        Principal = { Service = "ssm.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.raw.arn
      },
      {
        Sid    = "SSMBucketDelivery"
        Effect = "Allow"
        Principal = { Service = "ssm.amazonaws.com" }
        Action   = ["s3:PutObject", "s3:PutObjectAcl"]
        Resource = "${aws_s3_bucket.raw.arn}/ssm/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl"       = "bucket-owner-full-control"
            "aws:SourceAccount"  = var.account_id
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.raw]
}

# ── SSM Resource Data Sync ─────────────────────────────────────────────────────
resource "aws_ssm_resource_data_sync" "fleet" {
  name = "${var.project_name}-fleet-sync"
  s3_destination {
    bucket_name = aws_s3_bucket.raw.bucket
    prefix      = "ssm/"
    region      = var.aws_region
  }

  depends_on = [aws_s3_bucket_policy.raw_ssm]
}

# ── Curated bucket (Glue ETL writes Parquet here) ─────────────────────────────
resource "aws_s3_bucket" "curated" {
  bucket        = "${var.project_name}-curated-${var.environment}"
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_versioning" "curated" {
  bucket = aws_s3_bucket.curated.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "curated" {
  bucket = aws_s3_bucket.curated.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "curated" {
  bucket                  = aws_s3_bucket.curated.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "curated" {
  bucket = aws_s3_bucket.curated.id
  rule {
    id     = "transition-to-ia"
    status = "Enabled"
    filter { prefix = "" }
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    expiration { days = 365 }
  }
}

# ── Athena results bucket ──────────────────────────────────────────────────────
resource "aws_s3_bucket" "athena_results" {
  bucket        = "${var.project_name}-athena-results-${var.environment}"
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
