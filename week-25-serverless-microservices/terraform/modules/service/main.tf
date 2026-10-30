# Three microservices behind one HTTP API, sharing one DynamoDB table.
#
# WHY THREE, AND WHY THEY LOOK THE SAME
# -------------------------------------
# checkout is the one that matters. reports and exports are the neighbours.
# All three are generated from the same module with the same memory, the same
# runtime and the same table, because the week's claim is about what they
# SHARE, not about how they differ. If they differed in anything that affects
# scaling, the result would be arguable.
#
# None of them sets reserved concurrency. That is the point: a function with no
# reservation draws on the account's unreserved pool, and AWS documents that
# pool as shared across every function in the region. The experiment is whether
# "shared" means what people assume it means.

locals {
  # A tiny handler. The duration matters more than the work: concurrency is
  # (requests per second) x (duration), so a slow function holds an execution
  # environment open and consumes the pool faster than a fast one.
  services = {
    checkout = { duration_ms = var.checkout_duration_ms, description = "the service that matters" }
    reports  = { duration_ms = var.neighbour_duration_ms, description = "noisy neighbour" }
    exports  = { duration_ms = var.neighbour_duration_ms, description = "noisy neighbour" }
  }
}

resource "aws_dynamodb_table" "shared" {
  name         = "${var.name}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  # On-demand, so the table is never the bottleneck. The week is about Lambda
  # concurrency; a provisioned table would introduce a second throttle and make
  # the finding ambiguous.
  tags = var.tags
}

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

resource "aws_iam_role" "fn" {
  for_each           = local.services
  name               = "${var.name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.assume.json
  tags               = var.tags
}

data "aws_iam_policy_document" "fn" {
  for_each = local.services

  statement {
    sid       = "WriteItsOwnPartitionOnly"
    effect    = "Allow"
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem"]
    resources = [aws_dynamodb_table.shared.arn]
    # The table is shared, the partitions are not. Each service may only touch
    # keys prefixed with its own name -- a shared table is not a shared
    # dataset, and the boundary has to be written down to exist.
    condition {
      test     = "ForAllValues:StringLike"
      variable = "dynamodb:LeadingKeys"
      values   = ["${each.key}#*"]
    }
  }

  statement {
    sid       = "WriteIntoItsOwnLogGroupOnly"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.fn[each.key].arn}:*"]
  }
}

resource "aws_iam_role_policy" "fn" {
  for_each = local.services
  name     = "${var.name}-${each.key}"
  role     = aws_iam_role.fn[each.key].id
  policy   = data.aws_iam_policy_document.fn[each.key].json
}

resource "aws_cloudwatch_log_group" "fn" {
  for_each          = local.services
  name              = "/aws/lambda/${var.name}-${each.key}"
  retention_in_days = 7
  tags              = var.tags
}

data "archive_file" "fn" {
  for_each    = local.services
  type        = "zip"
  source_file = "${path.module}/../../../src/${each.key}/handler.py"
  output_path = "${path.module}/.build/${each.key}.zip"
}

resource "aws_lambda_function" "fn" {
  for_each = local.services

  function_name    = "${var.name}-${each.key}"
  role             = aws_iam_role.fn[each.key].arn
  handler          = "handler.handler"
  runtime          = "python3.13"
  filename         = data.archive_file.fn[each.key].output_path
  source_code_hash = data.archive_file.fn[each.key].output_base64sha256
  timeout          = 30
  memory_size      = 256

  # THE ONE VARIABLE THAT CHANGES BETWEEN THE TWO RUNS.
  #
  # run 1 (protect_checkout = false): -1 means "no reservation". Every service,
  #   checkout included, draws on the account's shared unreserved pool.
  #
  # run 2 (protect_checkout = true): checkout alone gets a reservation. No
  #   other function can consume it. Note what the docs also say and most
  #   people do not expect -- a reserved function can no longer borrow from
  #   the unreserved pool either. The reservation is a floor AND a ceiling.
  #
  # Nothing else differs between the runs: same load, same code, same region.
  reserved_concurrent_executions = (
    var.protect_checkout && each.key == "checkout"
    ? var.checkout_reserved_concurrency
    : lookup(var.neighbour_reservation, each.key, -1)
  )

  environment {
    variables = {
      TABLE       = aws_dynamodb_table.shared.name
      SERVICE     = each.key
      DURATION_MS = tostring(each.value.duration_ms)
    }
  }

  # Depend on the whole set, not fn[each.key] -- depends_on takes a static
  # reference only. The effect is the same: no function is created before its
  # log group exists, so Lambda cannot create an unretained one first.
  depends_on = [aws_cloudwatch_log_group.fn]
  tags       = merge(var.tags, { Service = each.key })
}

# ---------------------------------------------------------------------------
# One HTTP API, three routes. HTTP API rather than REST API: roughly a third
# the price per million requests, and none of the REST features are needed
# here. The API is not the subject of the week, so it should not be the
# expensive part of it.
# ---------------------------------------------------------------------------
resource "aws_apigatewayv2_api" "this" {
  name          = var.name
  protocol_type = "HTTP"
  tags          = var.tags
}

resource "aws_apigatewayv2_integration" "fn" {
  for_each               = local.services
  api_id                 = aws_apigatewayv2_api.this.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.fn[each.key].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "fn" {
  for_each  = local.services
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "POST /${each.key}"
  target    = "integrations/${aws_apigatewayv2_integration.fn[each.key].id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    # Left generous on purpose. A throttle here would stop the load before it
    # ever reached Lambda, and the week would measure API Gateway instead.
    throttling_burst_limit = 5000
    throttling_rate_limit  = 10000
  }

  tags = var.tags
}

resource "aws_lambda_permission" "apigw" {
  for_each      = local.services
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.fn[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.this.execution_arn}/*/*"
}
