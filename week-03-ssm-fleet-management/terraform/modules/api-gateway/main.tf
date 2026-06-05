###############################################################################
# API Gateway — Week 3 SSM Fleet Management
# POST /fleet  → webhook_receiver Lambda
###############################################################################

data "aws_region" "current" {}

resource "aws_api_gateway_rest_api" "this" {
  name        = "${var.project}-${var.environment}-fleet-api"
  description = "SSM Fleet Management self-service API"

  endpoint_configuration { types = ["REGIONAL"] }
  tags = { Name = "${var.project}-${var.environment}-fleet-api" }
}

resource "aws_api_gateway_resource" "fleet" {
  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = "fleet"
}

resource "aws_api_gateway_method" "post" {
  rest_api_id   = aws_api_gateway_rest_api.this.id
  resource_id   = aws_api_gateway_resource.fleet.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda" {
  rest_api_id             = aws_api_gateway_rest_api.this.id
  resource_id             = aws_api_gateway_resource.fleet.id
  http_method             = aws_api_gateway_method.post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "arn:aws:apigateway:${data.aws_region.current.name}:lambda:path/2015-03-31/functions/${var.webhook_receiver_invoke_arn}/invocations"
}

resource "aws_api_gateway_deployment" "this" {
  rest_api_id = aws_api_gateway_rest_api.this.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.fleet,
      aws_api_gateway_method.post,
      aws_api_gateway_integration.lambda,
    ]))
  }

  lifecycle { create_before_destroy = true }
}

resource "aws_api_gateway_stage" "this" {
  deployment_id = aws_api_gateway_deployment.this.id
  rest_api_id   = aws_api_gateway_rest_api.this.id
  stage_name    = var.environment

  tags = { Name = "${var.project}-${var.environment}-fleet-api-stage" }
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.webhook_receiver_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.this.execution_arn}/*/*"
}
