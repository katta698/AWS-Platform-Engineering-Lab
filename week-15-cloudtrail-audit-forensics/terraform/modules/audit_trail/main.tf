###############################################################################
# audit_trail
#
# The capture layer: the bucket CloudTrail writes into, the policy that lets it,
# the lifecycle rules that bound the cost, and the organization trail itself.
#
# The decision that shapes this module: MANAGEMENT EVENTS ONLY.
#
#   Management events -- the first copy delivered to S3 is FREE. Additional
#   copies are $2.00 per 100,000.
#   Data events      -- $0.10 per 100,000 from the FIRST copy, with no free
#   tier at all, and they are generated per object access. A single busy bucket
#   can produce more data events in an hour than the entire org produces
#   management events in a month.
#
# Every question this week sets out to answer -- who deleted the resource, what
# did this principal do, what changed outside Terraform, was the root account
# used -- is a management event. So the capture costs nothing to deliver and the
# only real spend is S3 storage and Athena scans.
#
# If a future week needs object-level access auditing, that is a data event
# question and it needs its own cost conversation first.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_organizations_organization" "current" {}

###############################################################################
# Log bucket
###############################################################################

resource "aws_s3_bucket" "trail" {
  bucket = var.bucket_name

  # Demo-and-delete build holding regenerable audit data. Without this, teardown
  # fails on a non-empty bucket and leaves a billed resource behind.
  force_destroy = true

  tags = { Name = var.bucket_name }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  bucket = aws_s3_bucket.trail.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "trail" {
  bucket = aws_s3_bucket.trail.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  bucket = aws_s3_bucket.trail.id

  rule {
    id     = "expire-audit-logs"
    status = "Enabled"

    filter {
      prefix = "AWSLogs/"
    }

    expiration {
      days = var.log_retention_days
    }
  }

  # Versioning is on, so the rule above only writes delete markers -- the actual
  # bytes stay billable as noncurrent versions until this rule removes them.
  # Without this pair, "expiry is configured" and "storage stops growing" are
  # different statements.
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 7
    }
  }

  # Orphaned partial uploads are invisible in the console object listing and
  # billed regardless.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "expire-athena-results"
    status = "Enabled"

    filter {
      prefix = "athena-results/"
    }

    expiration {
      days = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.trail]
}

###############################################################################
# Bucket policy
#
# An ORGANIZATION trail writes under AWSLogs/<org-id>/<account-id>/... rather
# than AWSLogs/<account-id>/..., so the policy has to grant the org prefix as
# well as the management account's own. Granting only the account prefix is a
# common and confusing failure: the trail creates successfully and member-account
# deliveries are silently denied.
###############################################################################

data "aws_iam_policy_document" "bucket" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${var.home_region}:${data.aws_caller_identity.current.account_id}:trail/${var.name_prefix}-org-trail"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWriteOrg"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    # Both prefixes. The org prefix carries every member account's events; the
    # bare account prefix is still used for some management-account deliveries.
    resources = [
      "${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_organizations_organization.current.id}/*",
      "${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudtrail:${var.home_region}:${data.aws_caller_identity.current.account_id}:trail/${var.name_prefix}-org-trail"]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["s3:*"]
    resources = [aws_s3_bucket.trail.arn, "${aws_s3_bucket.trail.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.trail]
}

###############################################################################
# The trail
###############################################################################

resource "aws_cloudtrail" "org" {
  name           = "${var.name_prefix}-org-trail"
  s3_bucket_name = aws_s3_bucket.trail.id

  is_organization_trail         = var.is_organization_trail
  is_multi_region_trail         = var.is_multi_region_trail
  include_global_service_events = true
  enable_log_file_validation    = var.enable_log_file_validation
  enable_logging                = true

  # No event_selector / advanced_event_selector block at all.
  #
  # That absence is the design decision, not an omission: with no selector,
  # CloudTrail records management events only, which is exactly what is wanted
  # here and is the copy that costs nothing to deliver. Adding a selector to
  # capture data events would change the cost model completely -- see the module
  # header.

  tags = { Name = "${var.name_prefix}-org-trail" }

  # The bucket policy must exist first, or CreateTrail fails its write check
  # with an unhelpful "insufficient permissions" error that looks like an IAM
  # problem rather than a bucket-policy one.
  depends_on = [aws_s3_bucket_policy.trail]
}
