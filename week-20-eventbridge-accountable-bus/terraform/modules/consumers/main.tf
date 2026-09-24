# Rules, targets, and the machinery that makes a silent failure audible.
#
# THE DETECTION PROBLEM THIS MODULE EXISTS TO SOLVE
#
# EventBridge publishes a `MatchedEvents` metric per RULE. There is no metric
# anywhere for "events that matched no rule at all" -- the thing you most want
# to know. An event that matches nothing is not an error; it is a successful
# publish with no subscriber, and AWS has no opinion about it.
#
# So the detection has to be built, and the only way to build it is a CATCH-ALL
# RULE: a rule whose pattern matches everything, so every event is guaranteed to
# match at least one rule. Then:
#
#     unmatched = catch_all.MatchedEvents - orders.MatchedEvents
#
# which is a CloudWatch metric-math expression, not a Lambda.
#
# THE TRADE, STATED PLAINLY: you buy that visibility with a second delivery.
# Every event now goes to the log group as well as wherever it was going, and
# you pay ingestion and storage for it. Visibility is not free and the bill is
# where it shows up. A post that presents the catch-all as a neat trick without
# saying that is selling something.

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# CONSUMER
# ---------------------------------------------------------------------------

data "archive_file" "consumer" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambda/consumer"
  output_path = "${path.module}/consumer.zip"
  excludes    = ["__pycache__"]
}

data "aws_iam_policy_document" "consumer_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "consumer" {
  name               = "${var.name_prefix}-consumer"
  assume_role_policy = data.aws_iam_policy_document.consumer_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "consumer_logs" {
  role       = aws_iam_role.consumer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Declared explicitly rather than letting Lambda create it implicitly, so the
# retention is set. An implicitly-created group defaults to never expire, which
# is a standing charge nobody remembers to look for.
resource "aws_cloudwatch_log_group" "consumer" {
  name              = "/aws/lambda/${var.name_prefix}-consumer"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_lambda_function" "consumer" {
  function_name    = "${var.name_prefix}-consumer"
  role             = aws_iam_role.consumer.arn
  handler          = "handler.handler"
  runtime          = "python3.13"
  filename         = data.archive_file.consumer.output_path
  source_code_hash = data.archive_file.consumer.output_base64sha256
  timeout          = 10

  environment {
    variables = {
      POISON_DETAIL_TYPE = var.poison_detail_type
    }
  }

  depends_on = [aws_cloudwatch_log_group.consumer]
  tags       = var.tags
}

resource "aws_lambda_permission" "orders" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.consumer.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.orders.arn
}

# ---------------------------------------------------------------------------
# DLQ -- proven with a real failed delivery, not a hand-pushed message
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "dlq" {
  name                      = "${var.name_prefix}-dlq"
  message_retention_seconds = 86400
  tags                      = var.tags
}

data "aws_iam_policy_document" "dlq" {
  statement {
    sid     = "AllowEventBridgeToSendFailedDeliveries"
    actions = ["sqs:SendMessage"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    resources = [aws_sqs_queue.dlq.arn]

    # Without this condition any EventBridge rule in any account could write
    # here. The DLQ is a queue like any other; being a DLQ grants it nothing.
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.orders.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id
  policy    = data.aws_iam_policy_document.dlq.json
}

# ---------------------------------------------------------------------------
# THE SECOND QUEUE, AND WHY ONE IS NOT ENOUGH
# ---------------------------------------------------------------------------
#
# Measured on this build, not assumed:
#
#   Lambda      Invocations 5, Errors 3     (the function raised)
#   EventBridge FailedInvocations   none
#               InvocationsSentToDLQ none    (EventBridge saw no failure at all)
#
# The DLQ above stayed EMPTY while the function threw three times, and that is
# correct behaviour. EventBridge invokes a Lambda target ASYNCHRONOUSLY: its
# delivery succeeds the moment Lambda accepts the invocation. What the function
# does afterwards is not EventBridge's business, so it is not a delivery
# failure, so the DLQ never sees it.
#
# The EventBridge DLQ catches things like NO_PERMISSIONS, NO_RESOURCE,
# THROTTLING -- "I could not hand this over". A function that accepts an event
# and then fails needs LAMBDA's own on-failure destination, which is a
# different mechanism configured in a different place.
#
# So: two failure modes, two queues. Configuring only the first -- which is the
# one every tutorial shows -- means an entire class of failure lands nowhere.
resource "aws_sqs_queue" "function_failures" {
  name                      = "${var.name_prefix}-function-failures"
  message_retention_seconds = 86400
  tags                      = var.tags
}

resource "aws_iam_role_policy" "consumer_on_failure" {
  name = "send-to-failure-queue"
  role = aws_iam_role.consumer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.function_failures.arn
    }]
  })
}

resource "aws_lambda_function_event_invoke_config" "consumer" {
  function_name = aws_lambda_function.consumer.function_name

  # Lambda's OWN async retry, separate from the rule's retry_policy. Left at 0
  # so the failure reaches the destination immediately rather than after two
  # more attempts -- the default of 2 is what makes this look like a slow DLQ
  # rather than a different mechanism.
  maximum_retry_attempts = 0

  destination_config {
    on_failure {
      destination = aws_sqs_queue.function_failures.arn
    }
  }
}

# ---------------------------------------------------------------------------
# RULE 1 -- the real subscriber
# ---------------------------------------------------------------------------
#
# An event pattern is a FILTER, not a query. It can match values and prefixes;
# it cannot express "where this field is absent" the way SQL can. A typo in a
# detail-type produces no error at deploy time and no error at publish time --
# it produces silence, which is the failure this week is about.
resource "aws_cloudwatch_event_rule" "orders" {
  name           = "${var.name_prefix}-orders"
  event_bus_name = var.bus_name
  description    = "The real subscriber: order events this platform actually handles"

  event_pattern = jsonencode({
    source        = [var.event_source]
    "detail-type" = [var.handled_detail_type, var.poison_detail_type]
  })

  tags = var.tags
}

resource "aws_cloudwatch_event_target" "orders" {
  rule           = aws_cloudwatch_event_rule.orders.name
  event_bus_name = var.bus_name
  target_id      = "consumer"
  arn            = aws_lambda_function.consumer.arn

  # Zero retries so the DLQ path is provable in seconds rather than minutes.
  # In production this would be higher -- the point here is to make the
  # mechanism observable, not to model a real retry budget.
  retry_policy {
    maximum_retry_attempts       = 0
    maximum_event_age_in_seconds = 60
  }

  dead_letter_config {
    arn = aws_sqs_queue.dlq.arn
  }
}

# ---------------------------------------------------------------------------
# RULE 2 -- the catch-all that makes "matched nothing" measurable
# ---------------------------------------------------------------------------
#
# `prefix: ""` matches any source, which is how you say "everything" in an
# event pattern. There is no `{"*": true}`.
resource "aws_cloudwatch_log_group" "catch_all" {
  name              = "/aws/events/${var.name_prefix}-catch-all"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_cloudwatch_event_rule" "catch_all" {
  name           = "${var.name_prefix}-catch-all"
  event_bus_name = var.bus_name
  description    = "Matches everything, so unmatched events become countable"

  event_pattern = jsonencode({
    source = [{ prefix = "" }]
  })

  tags = var.tags
}

# EventBridge writes to a log group through a resource policy on the LOG GROUP,
# not through an IAM role on the rule. Getting this wrong produces a rule that
# looks correct and delivers nothing.
data "aws_iam_policy_document" "catch_all_logs" {
  statement {
    actions = ["logs:CreateLogStream", "logs:PutLogEvents"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "delivery.logs.amazonaws.com"]
    }
    resources = ["${aws_cloudwatch_log_group.catch_all.arn}:*"]

    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.catch_all.arn]
    }
  }
}

resource "aws_cloudwatch_log_resource_policy" "catch_all" {
  policy_name     = "${var.name_prefix}-catch-all-logs"
  policy_document = data.aws_iam_policy_document.catch_all_logs.json
}

resource "aws_cloudwatch_event_target" "catch_all" {
  rule           = aws_cloudwatch_event_rule.catch_all.name
  event_bus_name = var.bus_name
  target_id      = "catch-all-log"
  arn            = aws_cloudwatch_log_group.catch_all.arn
}

# ---------------------------------------------------------------------------
# ALARMS
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "alerts" {
  name = "${var.name_prefix}-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "alerts" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# THE ALARM THIS WEEK IS ABOUT.
#
# Metric math: everything the catch-all saw, minus everything the real rule
# saw. Anything above zero is an event that was published successfully and
# consumed by nobody.
#
# treat_missing_data = "notBreaching": no traffic means no events, which is not
# the same as undetected drift. The "is anything publishing at all" question is
# a different alarm and deliberately not conflated with this one.
resource "aws_cloudwatch_metric_alarm" "unmatched_events" {
  alarm_name          = "${var.name_prefix}-events-matched-no-rule"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"

  alarm_description = join(" ", [
    "An event was published to ${var.bus_name} that no subscriber rule matched.",
    "PutEvents returned 200 and the publisher believes it succeeded.",
    "Nothing consumed it and, without this alarm, nothing would ever say so."
  ])

  metric_query {
    id          = "unmatched"
    expression  = "everything - handled"
    label       = "Events that matched no subscriber rule"
    return_data = true
  }

  metric_query {
    id = "everything"
    metric {
      namespace   = "AWS/Events"
      metric_name = "MatchedEvents"
      dimensions  = { RuleName = aws_cloudwatch_event_rule.catch_all.name }
      period      = 300
      stat        = "Sum"
    }
  }

  metric_query {
    id = "handled"
    metric {
      namespace   = "AWS/Events"
      metric_name = "MatchedEvents"
      dimensions  = { RuleName = aws_cloudwatch_event_rule.orders.name }
      period      = 300
      stat        = "Sum"
    }
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
  tags          = var.tags
}

resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  alarm_name          = "${var.name_prefix}-dlq-not-empty"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = aws_sqs_queue.dlq.name }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_description = "A delivery failed and was captured. Without the DLQ it would simply be gone."
  alarm_actions     = [aws_sns_topic.alerts.arn]
  ok_actions        = [aws_sns_topic.alerts.arn]
  tags              = var.tags
}

resource "aws_cloudwatch_metric_alarm" "consumer_errors" {
  alarm_name          = "${var.name_prefix}-consumer-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.consumer.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_description = "The consumer raised. Distinct from a delivery failure -- this one arrived."
  alarm_actions     = [aws_sns_topic.alerts.arn]
  tags              = var.tags
}
