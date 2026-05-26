###############################################################################
# API Gateway — POST /provision → webhook_receiver Lambda
###############################################################################

locals {
  name        = "${var.project}-${var.environment}"
  common_tags = merge(var.tags, { Module = "api-gateway" })
}

data "aws_region" "current" {}

resource "aws_api_gateway_rest_api" "main" {
  name        = "${local.name}-db-api"
  description = "Self-service Aurora database provisioning API"

  endpoint_configuration { types = ["REGIONAL"] }

  tags = local.common_tags
}

resource "aws_api_gateway_resource" "provision" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "provision"
}

resource "aws_api_gateway_method" "post_provision" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.provision.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.provision.id
  http_method             = aws_api_gateway_method.post_provision.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${var.webhook_receiver_arn}/invocations"
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.webhook_receiver_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.main.execution_arn}/*/*"
}

resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  depends_on  = [aws_api_gateway_integration.lambda]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.environment

  tags = local.common_tags
}
