###############################################################################
# Config recorder module -- this Lab's own AWS Config recorder.
#
# Added 2026-07-29 after the account's previous recorder (owned by an
# unrelated telemetry-dashboard project, borrowed via the "reuse an existing
# centrally-managed recorder" convention) was deleted as part of that other
# project's own cleanup -- confirmed via CloudTrail, not this project's doing.
# That deletion also silently broke Week 11's Security Hub FSBP controls
# (backed by Config), which is why this module both unblocks Week 12's own
# rules AND restores Week 11's dependency as a side effect -- no changes
# needed in Week 11's own Terraform.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# --- Delivery bucket: where Config writes configuration history/snapshots ----
resource "aws_s3_bucket" "config" {
  bucket        = "${var.name_prefix}-config-recorder-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "config" {
  bucket                  = aws_s3_bucket.config.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "config" {
  bucket = aws_s3_bucket.config.id

  rule {
    id     = "expire-config-history"
    status = "Enabled"
    filter {}

    expiration {
      days = var.delivery_history_retention_days
    }
  }
}

# --- IAM role Config assumes to record + write to the bucket ------------------
data "aws_iam_policy_document" "config_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "config_recorder" {
  name               = "${var.name_prefix}-config-recorder-role"
  assume_role_policy = data.aws_iam_policy_document.config_assume.json
  tags               = var.tags
}

# AWS-managed policy granting the broad read-only Describe/List/Get access
# Config needs across every recordable service -- hand-writing this per
# resource type isn't practical (hundreds of actions across 100+ services).
resource "aws_iam_role_policy_attachment" "config_managed" {
  role       = aws_iam_role.config_recorder.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AWS_ConfigRole"
}

# The managed policy above does NOT include bucket-specific write access --
# grant that directly to the recorder's own role (same-account IAM-role-based
# delivery, per AWS's documented "When Using IAM Roles" path) rather than a
# bucket policy trusting the config.amazonaws.com service principal.
resource "aws_iam_role_policy" "config_recorder_s3" {
  name = "${var.name_prefix}-config-recorder-s3-policy"
  role = aws_iam_role.config_recorder.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListAndCheckBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketAcl"]
        Resource = aws_s3_bucket.config.arn
      },
      {
        Sid      = "DeliverConfigHistory"
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.config.arn}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
    ]
  })
}

# --- The recorder itself: record everything, continuously ---------------------
resource "aws_config_configuration_recorder" "this" {
  name     = "${var.name_prefix}-recorder"
  role_arn = aws_iam_role.config_recorder.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }

  recording_mode {
    recording_frequency = "CONTINUOUS"
  }
}

resource "aws_config_delivery_channel" "this" {
  name           = "${var.name_prefix}-delivery-channel"
  s3_bucket_name = aws_s3_bucket.config.id
  depends_on     = [aws_config_configuration_recorder.this]
}

resource "aws_config_configuration_recorder_status" "this" {
  name       = aws_config_configuration_recorder.this.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.this]
}
