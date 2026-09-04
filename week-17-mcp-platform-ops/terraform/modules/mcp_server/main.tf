# The MCP server: a Lambda behind a Function URL, a cache that exists purely
# to stop a metered API being called in a loop, and the smallest IAM policy
# that lets four read-only tools work.
#
# WHY A FUNCTION URL AND NOT API GATEWAY
# This endpoint answers occasional sub-second questions. A Function URL has no
# hourly charge and no idle cost, and AWS_IAM auth means the caller's existing
# SSO identity is the authorization -- no Cognito user pool to run. The trade
# is that the client must sign requests with SigV4; a client that cannot needs
# API Gateway plus an OAuth provider, which is the production path and is
# documented in the README rather than built here.

locals {
  name = "${var.name_prefix}-mcp"

  tags = merge(var.tags, {
    Project   = "aws-platform-engineering-lab"
    Week      = "17"
    Component = "mcp-platform-ops"
    ManagedBy = "terraform"
  })
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --------------------------------------------------------------- packaging --
data "archive_file" "server" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambda/mcp_server"
  output_path = "${path.module}/build/mcp_server.zip"
  excludes    = ["__pycache__", "*.pyc"]
}

# ------------------------------------------------------------------- cache --
# Cost Explorer bills $0.01 per GetCostAndUsage request and each page counts
# separately. An LLM decides when to call a tool and will re-ask the same
# question inside one conversation, so without this table a chatty session
# quietly bills cents at a time. TTL is a DynamoDB attribute, not a policy:
# expired items are removed by the service at no cost.
resource "aws_dynamodb_table" "cost_cache" {
  name         = "${local.name}-cost-cache"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "cache_key"

  attribute {
    name = "cache_key"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  point_in_time_recovery {
    enabled = false # A cache. Losing it costs one Cost Explorer call.
  }

  tags = local.tags
}

# --------------------------------------------------------------------- iam --
data "aws_iam_policy_document" "assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "server" {
  name               = "${local.name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = local.tags
}

# Every statement here maps to exactly one tool. There is no write action of
# any kind in this policy -- not on the resources it reads, and not on the
# account. A model that is manipulated through a poisoned tool description can
# still only read, which turns a destruction risk into a disclosure one.
data "aws_iam_policy_document" "server" {
  # get_daily_cost
  statement {
    sid       = "CostExplorerRead"
    effect    = "Allow"
    actions   = ["ce:GetCostAndUsage"]
    resources = ["*"] # Cost Explorer has no resource-level ARNs.
  }

  # list_running_resources and find_untagged_resources
  statement {
    sid       = "TaggedResourceDiscovery"
    effect    = "Allow"
    actions   = ["tag:GetResources"]
    resources = ["*"] # The tagging API is account-wide by design.
  }

  # get_alarm_state
  statement {
    sid       = "AlarmRead"
    effect    = "Allow"
    actions   = ["cloudwatch:DescribeAlarms"]
    resources = ["*"]
  }

  # The cache, scoped to the one table rather than to DynamoDB generally.
  statement {
    sid       = "CostCache"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem"]
    resources = [aws_dynamodb_table.cost_cache.arn]
  }

  statement {
    sid       = "Logs"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.server.arn}:*"]
  }
}

resource "aws_iam_role_policy" "server" {
  name   = "${local.name}-read-only"
  role   = aws_iam_role.server.id
  policy = data.aws_iam_policy_document.server.json
}

# ------------------------------------------------------------------ lambda --
# Created explicitly rather than letting Lambda create it on first invoke, so
# retention is set. The implicit log group defaults to never expire, which
# accrues storage charges quietly and forever.
resource "aws_cloudwatch_log_group" "server" {
  name              = "/aws/lambda/${local.name}"
  retention_in_days = var.log_retention_days
  tags              = local.tags
}

resource "aws_lambda_function" "server" {
  function_name    = local.name
  role             = aws_iam_role.server.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.13"
  filename         = data.archive_file.server.output_path
  source_code_hash = data.archive_file.server.output_base64sha256

  # Tool calls are API round-trips, not computation. Memory is for the boto3
  # import; the tagging paginator over a few hundred resources is the slowest
  # path and finishes well inside this.
  memory_size = 512
  timeout     = 30

  environment {
    variables = {
      CACHE_TABLE       = aws_dynamodb_table.cost_cache.name
      CACHE_TTL_SECONDS = tostring(var.cache_ttl_seconds)
    }
  }

  depends_on = [aws_cloudwatch_log_group.server]
  tags       = local.tags
}

# AWS_IAM auth: every request must be SigV4-signed by a principal allowed to
# invoke this URL. Unauthenticated callers get a 403 from Lambda itself,
# before any of our code runs.
resource "aws_lambda_function_url" "server" {
  function_name      = aws_lambda_function.server.function_name
  authorization_type = "AWS_IAM"
}

# ---------------------------------------------------------------- alarming --
# A tool that fails silently is worse than one that is absent: the model simply
# reports it found nothing, and the human believes it.
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${local.name}-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = aws_lambda_function.server.function_name }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  # A period with no invocations is not a failure -- this server is idle by
  # nature, so missing data must not read as an alarm.
  treat_missing_data = "notBreaching"

  alarm_actions = var.alarm_sns_topic_arn == "" ? [] : [var.alarm_sns_topic_arn]
  tags          = local.tags
}
