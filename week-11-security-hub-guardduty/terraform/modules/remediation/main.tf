###############################################################################
# Remediation backbone — EventBridge routing, Lambda actors, SNS, DLQ.
#
# Two auto-remediators react to Security Hub CSPM findings and fix them
# (tag-gated); one notifier reacts to native GuardDuty threat findings and only
# escalates to a human. All three share one SNS topic and one DLQ. Failed async
# invocations land in the DLQ — a dropped security action must never be silent.
###############################################################################

data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition

  # Shared env every function receives.
  common_env = {
    SNS_TOPIC_ARN = aws_sns_topic.alerts.arn
  }

  # Per-Lambda definition: handler source dir name == each.key, plus its event
  # pattern, extra env, and the extra IAM statements it needs beyond the shared
  # logs/sns/dlq grant.
  lambdas = {
    sg_remediator = {
      description = "Revoke world-open management-port ingress on tagged security groups"
      timeout     = 30
      env = {
        REMEDIATION_TAG_KEY   = var.remediation_tag_key
        REMEDIATION_TAG_VALUE = var.remediation_tag_value
        HIGH_RISK_PORTS       = var.high_risk_ports
      }
      event_pattern = jsonencode({
        source      = ["aws.securityhub"]
        detail-type = ["Security Hub Findings - Imported"]
        detail = {
          findings = {
            Compliance  = { SecurityControlId = ["EC2.13", "EC2.14", "EC2.19"] }
            RecordState = ["ACTIVE"]
            # NEW only — matching NOTIFIED too would re-trigger this rule off
            # the Lambda's own BatchUpdateFindings->NOTIFIED writeback (an
            # infinite feedback loop; found live 2026-07-21). Security Hub
            # resets Workflow to NEW if a resolved finding later recurs, so
            # recurrences are still caught.
            Workflow = { Status = ["NEW"] }
          }
        }
      })
      # ec2:RevokeSecurityGroupIngress is IAM-scoped to tagged SGs as well — the
      # code checks the tag AND IAM refuses the call on anything untagged.
      statements = [
        {
          Sid      = "DescribeSecurityGroups"
          Effect   = "Allow"
          Action   = ["ec2:DescribeSecurityGroups"]
          Resource = "*"
        },
        {
          Sid      = "RevokeTaggedSecurityGroupIngress"
          Effect   = "Allow"
          Action   = ["ec2:RevokeSecurityGroupIngress"]
          Resource = "*"
          Condition = {
            StringEquals = {
              "aws:ResourceTag/${var.remediation_tag_key}" = var.remediation_tag_value
            }
          }
        },
        {
          Sid      = "UpdateFindings"
          Effect   = "Allow"
          Action   = ["securityhub:BatchUpdateFindings"]
          Resource = "*"
        },
      ]
    }

    s3_remediator = {
      description = "Apply S3 Block Public Access to tagged public buckets"
      timeout     = 30
      env = {
        REMEDIATION_TAG_KEY   = var.remediation_tag_key
        REMEDIATION_TAG_VALUE = var.remediation_tag_value
      }
      event_pattern = jsonencode({
        source      = ["aws.securityhub"]
        detail-type = ["Security Hub Findings - Imported"]
        detail = {
          findings = {
            Compliance  = { SecurityControlId = ["S3.2", "S3.3", "S3.8"] }
            RecordState = ["ACTIVE"]
            # NEW only — matching NOTIFIED too would re-trigger this rule off
            # the Lambda's own BatchUpdateFindings->NOTIFIED writeback (an
            # infinite feedback loop; found live 2026-07-21). Security Hub
            # resets Workflow to NEW if a resolved finding later recurs, so
            # recurrences are still caught.
            Workflow = { Status = ["NEW"] }
          }
        }
      })
      statements = [
        {
          Sid      = "ReadBucketTags"
          Effect   = "Allow"
          Action   = ["s3:GetBucketTagging"]
          Resource = "arn:${local.partition}:s3:::*"
        },
        {
          Sid      = "BlockPublicAccess"
          Effect   = "Allow"
          Action   = ["s3:PutBucketPublicAccessBlock"]
          Resource = "arn:${local.partition}:s3:::*"
        },
        {
          Sid      = "UpdateFindings"
          Effect   = "Allow"
          Action   = ["securityhub:BatchUpdateFindings"]
          Resource = "*"
        },
      ]
    }

    threat_notifier = {
      description = "Escalate GuardDuty threat findings to SNS (no auto-mutation)"
      timeout     = 15
      env = {
        GUARDDUTY_MIN_SEVERITY = var.guardduty_min_severity
      }
      event_pattern = jsonencode({
        source      = ["aws.guardduty"]
        detail-type = ["GuardDuty Finding"]
      })
      statements = [] # notify-only: no mutating permissions at all
    }
  }
}

# --- Shared SNS topic + email subscription -------------------------------------
resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# --- Shared dead-letter queue for failed async invocations ---------------------
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-remediation-dlq"
  message_retention_seconds = 1209600 # 14 days — max, so a failure is never lost
  tags                      = var.tags
}

# --- Per-Lambda IAM role -------------------------------------------------------
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  for_each           = local.lambdas
  name               = "${var.name_prefix}-${each.key}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = local.lambdas
  name              = "/aws/lambda/${var.name_prefix}-${each.key}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_iam_role_policy" "lambda" {
  for_each = local.lambdas
  name     = "${var.name_prefix}-${each.key}-policy"
  role     = aws_iam_role.lambda[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid      = "Logs"
          Effect   = "Allow"
          Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
          Resource = "${aws_cloudwatch_log_group.lambda[each.key].arn}:*"
        },
        {
          Sid      = "PublishAlerts"
          Effect   = "Allow"
          Action   = ["sns:Publish"]
          Resource = aws_sns_topic.alerts.arn
        },
        {
          Sid      = "SendToDlq"
          Effect   = "Allow"
          Action   = ["sqs:SendMessage"]
          Resource = aws_sqs_queue.dlq.arn
        },
      ],
      each.value.statements,
    )
  })
}

# --- Lambda functions (prebuilt zips, committed — HCP VCS runs can't build) ----
resource "aws_lambda_function" "this" {
  for_each         = local.lambdas
  function_name    = "${var.name_prefix}-${each.key}"
  description      = each.value.description
  role             = aws_iam_role.lambda[each.key].arn
  runtime          = "python3.13"
  handler          = "handler.lambda_handler"
  timeout          = each.value.timeout
  memory_size      = 128
  filename         = "${path.module}/../../../lambda/${each.key}/${each.key}.zip"
  source_code_hash = filebase64sha256("${path.module}/../../../lambda/${each.key}/${each.key}.zip")

  environment {
    variables = merge(local.common_env, each.value.env)
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.dlq.arn
  }

  # Ensure the log group exists (and its retention) before first invocation.
  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy.lambda,
  ]

  tags = var.tags
}

# --- EventBridge rules + targets + invoke permission ---------------------------
resource "aws_cloudwatch_event_rule" "this" {
  for_each      = local.lambdas
  name          = "${var.name_prefix}-${each.key}"
  description   = each.value.description
  event_pattern = each.value.event_pattern
  tags          = var.tags
}

resource "aws_cloudwatch_event_target" "lambda" {
  for_each  = local.lambdas
  rule      = aws_cloudwatch_event_rule.this[each.key].name
  target_id = each.key
  arn       = aws_lambda_function.this[each.key].arn
}

resource "aws_lambda_permission" "events" {
  for_each      = local.lambdas
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this[each.key].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this[each.key].arn
}

# --- Safety alarm: the remediation layer failing must itself page a human ------
resource "aws_cloudwatch_metric_alarm" "dlq_not_empty" {
  alarm_name          = "${var.name_prefix}-remediation-dlq-not-empty"
  alarm_description   = "A remediation Lambda failed and its event landed in the DLQ. Investigate."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.dlq.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}
