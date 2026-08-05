###############################################################################
# Protected application -- the thing the firewall is in front of.
#
#   CloudFront distribution  (edge,   CLOUDFRONT-scope web ACL)
#            |
#            v
#   API Gateway REST API     (origin, REGIONAL-scope web ACL)
#            |
#            v
#   Lambda echo function
#
# The origin is intentionally trivial. It exists so that "did the request get
# through?" has an observable answer, and so the week has something to protect
# that costs nothing while idle.
#
# REST API, not HTTP API: AWS WAF cannot be associated with an API Gateway
# HTTP API at all. This is a hard constraint, not a preference -- picking an
# HTTP API here would make the entire regional half of the design impossible.
###############################################################################

data "aws_region" "current" {}

###############################################################################
# Lambda echo origin
###############################################################################

data "archive_file" "echo" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/.build/${var.name_prefix}-echo.zip"
  excludes    = ["__pycache__", "*.pyc"]
}

resource "aws_iam_role" "lambda" {
  name = "${var.name_prefix}-echo-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

# The echo function talks to nothing. Logs are its only permission, so the
# managed basic-execution policy is the whole grant -- no inline policy needed.
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Created explicitly rather than letting Lambda create it implicitly, so that
# retention is bounded. An implicitly-created Lambda log group defaults to
# never expire.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.name_prefix}-echo"
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_lambda_function" "echo" {
  function_name    = "${var.name_prefix}-echo"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.echo.output_path
  source_code_hash = data.archive_file.echo.output_base64sha256
  timeout          = 10
  memory_size      = 128

  environment {
    variables = {
      STAGE = var.stage_name
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_logs,
    aws_cloudwatch_log_group.lambda,
  ]

  tags = var.tags
}

###############################################################################
# API Gateway REST API
###############################################################################

resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.name_prefix}-api"
  description = "Echo API behind AWS WAF -- Week 13."

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
}

# A greedy proxy resource so every path reaches the echo function. The attack
# simulation needs to send requests to paths like /admin and /../../etc/passwd
# and have them be *routed* -- if the API 404'd on unknown paths, WAF's verdict
# and the API's routing would be indistinguishable in the response.
resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "proxy" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.proxy.id
  http_method             = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.echo.invoke_arn
}

# The root path is a separate resource from {proxy+} in REST APIs -- without
# this, GET / returns a 403 "Missing Authentication Token" that looks like a
# WAF block but is not one.
resource "aws_api_gateway_method" "root" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_rest_api.this.root_resource_id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "root" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_rest_api.this.root_resource_id
  http_method             = aws_api_gateway_method.root.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.echo.invoke_arn
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.echo.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  # REST API deployments are snapshots. Without a trigger keyed to the actual
  # configuration, Terraform will not redeploy after a routing change and the
  # live stage silently serves the previous version.
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.proxy.id,
      aws_api_gateway_method.proxy.id,
      aws_api_gateway_integration.proxy.id,
      aws_api_gateway_method.root.id,
      aws_api_gateway_integration.root.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "this" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  deployment_id = aws_api_gateway_deployment.this.id
  stage_name    = var.stage_name

  tags = var.tags
}

###############################################################################
# CloudFront distribution
#
# Shield Standard's L3/L4 protection applies here at the edge. That is the one
# thing genuinely gained by putting CloudFront in front rather than exposing
# the API directly -- along with a second, independent WAF evaluation.
###############################################################################

# Managed policies rather than hand-rolled ones. CachingDisabled because this
# is a demo origin whose entire purpose is that every request reaches it --
# a cached response would mean the origin never sees the second request and
# the rate-limit test would measure nothing.
data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

# AllViewerExceptHostHeader: forwards the viewer's headers, cookies, and query
# string to the origin -- which the WAF and the echo function both need to see
# -- while letting CloudFront set the Host header to the API Gateway domain.
# Forwarding the original Host would break API Gateway's request routing.
data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "this" {
  enabled         = true
  comment         = "${var.name_prefix} -- WAF-protected echo API"
  is_ipv6_enabled = true

  origin {
    domain_name = "${aws_api_gateway_rest_api.this.id}.execute-api.${data.aws_region.current.region}.amazonaws.com"
    origin_id   = "api-gateway"

    # The stage name is part of a REST API's path, so it belongs in
    # origin_path. This keeps the public URL clean: /foo at the edge becomes
    # /prod/foo at the origin.
    origin_path = "/${var.stage_name}"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id = "api-gateway"

    # Redirect rather than allow-all: an attack simulation sending a payload
    # over plaintext HTTP would otherwise transit the internet unencrypted.
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods  = ["GET", "HEAD"]

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # Attached directly as an attribute -- CloudFront does not use
  # aws_wafv2_web_acl_association.
  web_acl_id = var.cloudfront_web_acl_arn

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  # PriceClass_100 (North America + Europe) rather than the all-edge default.
  # This is a demo with a single tester; paying for edge locations in every
  # region buys nothing.
  price_class = "PriceClass_100"

  tags = var.tags
}
