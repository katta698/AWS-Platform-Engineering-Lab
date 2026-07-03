locals {
  name_prefix = "${var.project}-${var.environment}"
  bucket_name = "${local.name_prefix}-${var.account_id}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
    Week        = "08"
  }
}

resource "aws_s3_bucket" "main" {
  bucket = local.bucket_name
  tags   = local.common_tags
}

resource "aws_s3_bucket_versioning" "main" {
  bucket = aws_s3_bucket.main.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "main" {
  bucket = aws_s3_bucket.main.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket                  = aws_s3_bucket.main.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Intelligent-Tiering: auto-moves objects based on access patterns.
# Archive tiers activate after the configured inactivity periods.
# Objects <128KB are exempt from monitoring charges and stay in Frequent Access.
resource "aws_s3_bucket_intelligent_tiering_configuration" "main" {
  bucket = aws_s3_bucket.main.id
  name   = "entire-bucket"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = var.intelligent_tiering_archive_days
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = var.intelligent_tiering_deep_archive_days
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "main" {
  bucket = aws_s3_bucket.main.id

  depends_on = [aws_s3_bucket_versioning.main]

  # logs/ prefix: deterministic transitions for predictable access patterns
  rule {
    id     = "logs-tiering"
    status = "Enabled"

    filter {
      prefix = "logs/"
    }

    transition {
      days          = var.logs_ia_transition_days
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = var.logs_glacier_transition_days
      storage_class = "GLACIER_IR"
    }

    expiration {
      days = var.logs_expiration_days
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }

  # Abort stalled multipart uploads — orphaned parts bill at Standard rates forever without this
  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Clean up old object versions — without this, every overwrite accumulates storage silently
  rule {
    id     = "noncurrent-version-cleanup"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }
}

# S3 fires an event for every object created; SQS buffers it for object_tagger Lambda
resource "aws_s3_bucket_notification" "main" {
  bucket      = aws_s3_bucket.main.id
  depends_on  = [aws_s3_bucket_public_access_block.main]

  queue {
    queue_arn = var.sqs_queue_arn
    events    = ["s3:ObjectCreated:*"]
  }
}
