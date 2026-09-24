# The bus, and the four things that make it answerable.
#
# An event bus is the easiest thing in AWS to deploy and one of the hardest to
# debug. Publishing succeeds whether or not anything is listening. There is no
# compile step, no contract, and no error when a payload changes shape. This
# module adds the four mechanisms that turn "it stopped working" into something
# you can actually investigate:
#
#   archive      -> can I get the event back?
#   discoverer   -> what did it actually look like?
#   CloudTrail   -> who published it?
#   (DLQ lives in the consumers module -> what failed to deliver?)
#
# WHY A CUSTOM BUS AND NOT `default`
# The default bus already carries every AWS service event in the account. A
# discoverer pointed at it would infer schemas for unrelated traffic and an
# archive would store it, at $0.023/GB/month. There is also an unrelated
# `ebs-savings-governance-bus` in this account from a different project --
# neither is this lab's to touch.

resource "aws_cloudwatch_event_bus" "this" {
  name = var.bus_name
  tags = var.tags
}

# ---------------------------------------------------------------------------
# ARCHIVE -- the only mechanism that makes a past event re-deliverable
# ---------------------------------------------------------------------------
#
# Worth knowing before relying on it: a replay re-delivers to the rules that
# exist NOW, not the rules that existed when the event was archived. If a rule
# was deleted or its pattern edited, the replayed event follows today's routing.
# That is the difference between an archive and a backup, and it is tested in
# scripts/prove_unmatched.sh rather than asserted here.
#
# Cost shape: $0.10/GB to process into the archive, then $0.023/GB/month to
# keep. At lab volume both are rounding errors -- but the storage charge is the
# ONLY standing meter in this entire week, so it is the thing teardown exists
# for.
resource "aws_cloudwatch_event_archive" "this" {
  name             = "${var.bus_name}-archive"
  event_source_arn = aws_cloudwatch_event_bus.this.arn
  retention_days   = var.archive_retention_days

  description = "Replayable record of everything published to ${var.bus_name}"
}

# ---------------------------------------------------------------------------
# SCHEMA REGISTRY + DISCOVERER -- the contract, inferred from real traffic
# ---------------------------------------------------------------------------
#
# The discoverer writes what producers ACTUALLY send, not what a wiki says they
# send. That distinction is the entire value: a schema nobody updates is worse
# than no schema, because it is trusted.
#
# IMPORTANT AND EASY TO MISREAD: the registry does NOT enforce anything.
# EventBridge will happily accept an event that violates every schema it holds.
# This is discovery, not validation. Anyone reading "schema registry" and
# hearing "contract enforcement" is going to be surprised in production.
#
# Cost: free for the first 5,000,000 ingested events per month, then $1.00/M
# billed in 8 KB chunks. Lab volume is thousands, so this is free -- but it is
# metered, and a busy bus with discovery left on is a real bill.
resource "aws_schemas_discoverer" "this" {
  source_arn  = aws_cloudwatch_event_bus.this.arn
  description = "Infers schemas from live traffic on ${var.bus_name}"
  tags        = var.tags
}

# ---------------------------------------------------------------------------
# CLOUDTRAIL DATA EVENTS -- who published, and the half of the answer it gives
# ---------------------------------------------------------------------------
#
# Until 4 May 2026 this did not exist. Every EventBridge API was a MANAGEMENT
# event except the one that actually moves data: PutEvents and PutPartnerEvents
# are data-plane operations, and data events are off by default. So "who
# published this event?" was structurally unanswerable, not merely hard.
#
# TWO LIMITS THAT MATTER MORE THAN THE FEATURE:
#
# 1. THE PAYLOAD IS REDACTED. A data event records the caller, the IP, the
#    source, the detail-type and the event id -- and then `"detail":
#    "HIDDEN_DUE_TO_SECURITY_REASONS"`. CloudTrail tells you WHO and WHEN and
#    never WHAT. The archive above holds the payload but carries no identity.
#    Neither answers "what happened" alone; an investigation needs both, joined
#    on the event id.
#
# 2. CROSS-ACCOUNT ATTRIBUTION GOES TO THE CALLER, NOT THE BUS OWNER. If another
#    account publishes to this bus through a resource policy, THEIR account gets
#    the CloudTrail data event and this one does not. Owning the bus does not
#    mean seeing who wrote to it. Same for bus-to-bus forwarding: neither the
#    source bus owner nor the destination bus owner receives it.
#
# Data events are charged. The advanced event selector below is scoped to this
# one bus by ARN for exactly that reason -- an unscoped selector logs every
# PutEvents in the account, including the unrelated governance bus.
resource "aws_s3_bucket" "trail" {
  bucket        = "${var.bus_name}-trail-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = var.tags
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "trail_bucket" {
  statement {
    sid     = "AWSCloudTrailAclCheck"
    actions = ["s3:GetBucketAcl"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = [aws_s3_bucket.trail.arn]
  }

  statement {
    sid     = "AWSCloudTrailWrite"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.trail.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  bucket = aws_s3_bucket.trail.id
  policy = data.aws_iam_policy_document.trail_bucket.json
}

resource "aws_cloudtrail" "bus" {
  name                       = "${var.bus_name}-data-events"
  s3_bucket_name             = aws_s3_bucket.trail.id
  enable_log_file_validation = true

  # NO `event_selector` BLOCK HERE, and that is not an omission: the provider
  # rejects a trail that has both ("event_selector": conflicts with
  # advanced_event_selector). Caught by `terraform validate` before this ever
  # reached an apply.
  #
  # It costs nothing to lose, because advanced selectors are an ALLOWLIST: a
  # trail with only a Data selector does not log management events at all. That
  # is the outcome the basic block was reaching for anyway -- this account
  # already has a management-events trail, and a second copy bills $2.00/100k.
  advanced_event_selector {
    name = "Log PutEvents on ${var.bus_name} only"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }

    field_selector {
      field  = "resources.type"
      equals = ["AWS::Events::EventBus"]
    }

    # Scoped to this bus. Without this the selector logs every PutEvents in the
    # account, which is both noisy and billable.
    field_selector {
      field  = "resources.ARN"
      equals = [aws_cloudwatch_event_bus.this.arn]
    }
  }

  depends_on = [aws_s3_bucket_policy.trail]
  tags       = var.tags
}
