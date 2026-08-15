###############################################################################
# flow_logs
#
# The capture layer: the bucket logs land in, the lifecycle rules that stop it
# growing forever, the delivery role, and the flow log subscription itself.
#
# Three decisions in here are worth more than the rest of the file combined:
#
#   1. Destination is S3, not CloudWatch Logs. $0.25/GB vs $0.50/GB ingested,
#      and Parquet is only available on the S3 path. Both reasons independently
#      justify the choice; together they make it obvious.
#
#   2. Parquet + hive-compatible prefixes + hourly partitions. Columnar storage
#      means Athena reads only the columns a query names, and hourly partitions
#      mean it reads only the hours a query asks for. Athena bills $5 per TB
#      SCANNED, so these are not optimisations -- they ARE the cost model.
#
#   3. The delivery role carries ec2:DescribeTags and iam:CreateServiceLinkedRole.
#      Without them the v11 instance-tag field silently resolves to "-" on every
#      record. No error, no warning, no failed apply. Just a column of dashes
#      discovered days later.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

###############################################################################
# Destination bucket
###############################################################################

resource "aws_s3_bucket" "flow_logs" {
  bucket = var.bucket_name

  # This is a demo-and-delete build and the bucket fills with regenerable log
  # data. force_destroy lets teardown actually complete instead of failing on a
  # non-empty bucket and leaving a billed resource behind.
  force_destroy = true

  tags = { Name = var.bucket_name }
}

resource "aws_s3_bucket_public_access_block" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_versioning" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

# The rule that keeps this build from becoming a permanent bill.
resource "aws_s3_bucket_lifecycle_configuration" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id

  # Expire raw logs. Flow logs never stop arriving; something has to end them.
  rule {
    id     = "expire-raw-flow-logs"
    status = "Enabled"

    filter {
      prefix = "AWSLogs/"
    }

    expiration {
      days = var.log_retention_days
    }
  }

  # Versioning is on, so expiry only creates delete markers -- the actual bytes
  # stay billable as noncurrent versions until this rule removes them. Without
  # this second rule the first one deletes nothing you are charged for.
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }

  # Orphaned multipart uploads are invisible in the console object listing and
  # billed anyway. Every bucket that receives machine-generated writes wants this.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Athena query results are disposable the moment they have been read.
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

  depends_on = [aws_s3_bucket_versioning.flow_logs]
}

###############################################################################
# Bucket policy for the log delivery service
#
# Both the aws:SourceAccount and aws:SourceArn conditions are present to prevent
# the confused-deputy case where another account points its flow logs at this
# bucket. delivery.logs.amazonaws.com is the correct principal for vended logs.
###############################################################################

data "aws_iam_policy_document" "bucket" {
  statement {
    sid    = "AWSLogDeliveryWrite"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.flow_logs.arn}/AWSLogs/aws-account-id=${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
    }
  }

  statement {
    sid    = "AWSLogDeliveryAclCheck"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }

    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.flow_logs.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"]
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
    resources = [aws_s3_bucket.flow_logs.arn, "${aws_s3_bucket.flow_logs.arn}/*"]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "flow_logs" {
  bucket = aws_s3_bucket.flow_logs.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.flow_logs]
}

###############################################################################
# Flow log delivery role
#
# Publishing to S3 does not strictly require an IAM role -- but reading EC2 tag
# values for the v11 tag fields does. That is the whole reason this role exists.
###############################################################################

data "aws_iam_policy_document" "flow_log_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.name_prefix}-flow-logs-role"
  assume_role_policy = data.aws_iam_policy_document.flow_log_assume.json
}

data "aws_iam_policy_document" "flow_logs" {
  statement {
    sid    = "DeliverToS3"
    effect = "Allow"
    actions = [
      "logs:CreateLogDelivery",
      "logs:DeleteLogDelivery",
      "s3:PutObject",
      "s3:GetBucketAcl",
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.flow_logs.arn, "${aws_s3_bucket.flow_logs.arn}/*"]
  }

  # The two permissions that make the difference between real tag values and a
  # column full of "-". DescribeTags has no resource-level scoping, hence "*".
  statement {
    sid    = "ReadResourceTagsForV11TagFields"
    effect = "Allow"
    actions = [
      "ec2:DescribeTags",
      "autoscaling:DescribeTags",
    ]
    resources = ["*"]
  }

  # VPC Flow Logs creates a service-linked role the first time tag fields are
  # used in an account. Scoped to that one service so this is not a broad grant.
  statement {
    sid       = "CreateFlowLogsTagsServiceLinkedRole"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "flow_logs" {
  name   = "${var.name_prefix}-flow-logs-policy"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs.json
}

###############################################################################
# The flow log subscription
###############################################################################

resource "aws_flow_log" "this" {
  vpc_id                   = var.vpc_id
  traffic_type             = var.traffic_type
  log_destination_type     = "s3"
  log_destination          = aws_s3_bucket.flow_logs.arn
  log_format               = var.log_format
  max_aggregation_interval = var.max_aggregation_interval
  iam_role_arn             = aws_iam_role.flow_logs.arn

  destination_options {
    file_format = "parquet"

    # Produces prefixes shaped:
    #   AWSLogs/aws-account-id=<acct>/aws-service=vpcflowlogs/aws-region=<region>/
    #     year=YYYY/month=MM/day=DD/hour=HH/
    # The Glue table's storage.location.template must reproduce this exactly.
    hive_compatible_partitions = true
    per_hour_partition         = true
  }

  # Embeds the VALUE of each listed instance tag into every flow record, removing
  # the need to join flows against a resource inventory to find out who owns them.
  dynamic "tag_field_specification" {
    for_each = length(var.tag_keys) > 0 ? [1] : []

    content {
      resource_type = "instance"
      tag_keys      = var.tag_keys
    }
  }

  tags = { Name = "${var.name_prefix}-flow-log" }

  depends_on = [
    aws_s3_bucket_policy.flow_logs,
    aws_iam_role_policy.flow_logs,
  ]
}
