###############################################################################
# The workload the agent investigates.
#
# Small on purpose. This is not a demonstration of building something; it is a
# control specimen. What matters is that its failure has ONE known cause,
# established before the agent is asked, so the agent's conclusion can be
# graded instead of admired.
#
# The break this is designed for: revoke ssm:GetParameter from the execution
# role. Nothing about the deployment changes -- same code, same image, same
# configuration -- and the function starts failing. That is the interesting
# class of incident, because the obvious places to look (recent deploys, code
# diffs) are all clean.
#
# It is also the case Week 15 can grade, since an IAM policy change is a
# CloudTrail management event with a principal, a timestamp and a source IP
# attached to it. The agent produces a narrative; CloudTrail produces a fact.
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

###############################################################################
# Somewhere to write, and something to read
###############################################################################

resource "aws_s3_bucket" "records" {
  bucket        = "${var.name_prefix}-records-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"
  force_destroy = true # lab data only; teardown should never need a manual empty
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "records" {
  bucket                  = aws_s3_bucket.records.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "records" {
  bucket = aws_s3_bucket.records.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Records are disposable; nothing here should accumulate cost after the week.
resource "aws_s3_bucket_lifecycle_configuration" "records" {
  bucket = aws_s3_bucket.records.id

  rule {
    id     = "expire-lab-records"
    status = "Enabled"
    filter {}
    expiration {
      days = 7
    }
  }
}

resource "aws_ssm_parameter" "config" {
  name        = "/${var.name_prefix}/processing-mode"
  description = "Read on every invocation. Revoking the role's ssm:GetParameter is the deliberate break."
  type        = "String"
  value       = "standard"
  tags        = var.tags
}

###############################################################################
# The function
###############################################################################

data "archive_file" "processor" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambda/order_processor"
  output_path = "${path.module}/../../../lambda/builds/order_processor.zip"
}

resource "aws_iam_role" "processor" {
  name               = "${var.name_prefix}-processor"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = var.tags
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

# Split deliberately into two policies rather than one.
#
# The break is "revoke ssm:GetParameter", and it should be revocable WITHOUT
# touching anything else -- detaching one policy, leaving logging and S3 intact.
# A single combined policy would force the break to be an edit of a document
# that also governs unrelated permissions, which muddies what CloudTrail records
# and therefore muddies what the agent is being graded on.
resource "aws_iam_role_policy" "baseline" {
  name = "baseline"
  role = aws_iam_role.processor.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.name_prefix}-processor:*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:PutObject"]
        Resource = "${aws_s3_bucket.records.arn}/*"
      },
    ]
  })
}

# THIS is the one the lab detaches. Kept alone, named plainly, so the CloudTrail
# event for its removal is unambiguous.
resource "aws_iam_role_policy" "config_read" {
  name = "config-read"
  role = aws_iam_role.processor.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = aws_ssm_parameter.config.arn
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "processor" {
  name              = "/aws/lambda/${var.name_prefix}-processor"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_lambda_function" "processor" {
  function_name = "${var.name_prefix}-processor"
  role          = aws_iam_role.processor.arn
  handler       = "handler.handler"
  runtime       = "python3.12"

  # DECOY, on purpose.
  #
  # Bumped 15 -> 20 immediately before the second deliberate break, to put a
  # real, recent, innocent deployment in front of the actual cause. A recent
  # deploy is the most attractive explanation in any incident, and it is wrong
  # here -- the timeout has nothing to do with the failure.
  #
  # The first investigation found the true cause when it was the ONLY change in
  # the window. This tests whether it still does when a more obvious candidate
  # sits closer to the symptom in time.
  timeout          = 20
  filename         = data.archive_file.processor.output_path
  source_code_hash = data.archive_file.processor.output_base64sha256

  environment {
    variables = {
      CONFIG_PARAM_NAME = aws_ssm_parameter.config.name
      RECORDS_BUCKET    = aws_s3_bucket.records.id
    }
  }

  depends_on = [aws_cloudwatch_log_group.processor]
  tags       = var.tags
}

###############################################################################
# Keep it running, so a break shows up as a change rather than as silence
###############################################################################

resource "aws_cloudwatch_event_rule" "tick" {
  name                = "${var.name_prefix}-tick"
  description         = "Invokes the processor every 5 minutes so the failure appears as a break in a working series."
  schedule_expression = "rate(5 minutes)"
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "tick" {
  rule = aws_cloudwatch_event_rule.tick.name
  arn  = aws_lambda_function.processor.arn
}

resource "aws_lambda_permission" "events" {
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.tick.arn
}

# A static threshold, for the reason Week 15 settled: the correct number of
# errors is a fact, and it is zero. An anomaly band would learn a baseline error
# rate and stop reporting it.
#
# Period is deliberately SHORT here. Week 15 used a 24-hour period with Maximum
# and the alarm latched -- one event pinned it in ALARM and every later
# detection was a non-transition, so nothing was sent for two days. A 5-minute
# period over 1 datapoint recovers as soon as the workload does.
resource "aws_cloudwatch_metric_alarm" "processor_errors" {
  alarm_name          = "${var.name_prefix}-processor-errors"
  alarm_description   = "The order processor is failing. Errors should be zero; anything above that is a real break."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.processor.function_name
  }

  tags = var.tags
}
