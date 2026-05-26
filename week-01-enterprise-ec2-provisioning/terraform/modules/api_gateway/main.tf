###############################################################################
# Module: API Gateway
# REST API — POST /provision → Lambda servicenow_receiver
###############################################################################

# ── REST API ─────────────────────────────────────────────────────────────────
resource "aws_api_gateway_rest_api" "main" {
  name        = "${var.project}-${var.environment}-api"
  description = "ServiceNow webhook receiver for EC2 self-service provisioning"

  endpoint_configuration {
    types = ["REGIONAL"]
  }

  tags = var.tags
}

# ── /provision resource ───────────────────────────────────────────────────────
resource "aws_api_gateway_resource" "provision" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  parent_id   = aws_api_gateway_rest_api.main.root_resource_id
  path_part   = "provision"
}

# ── POST method ───────────────────────────────────────────────────────────────
resource "aws_api_gateway_method" "provision_post" {
  rest_api_id   = aws_api_gateway_rest_api.main.id
  resource_id   = aws_api_gateway_resource.provision.id
  http_method   = "POST"
  authorization = "NONE"
}

# ── Lambda integration ────────────────────────────────────────────────────────
resource "aws_api_gateway_integration" "provision_lambda" {
  rest_api_id             = aws_api_gateway_rest_api.main.id
  resource_id             = aws_api_gateway_resource.provision.id
  http_method             = aws_api_gateway_method.provision_post.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = var.lambda_invoke_arn
}

# ── Method response ───────────────────────────────────────────────────────────
resource "aws_api_gateway_method_response" "provision_200" {
  rest_api_id = aws_api_gateway_rest_api.main.id
  resource_id = aws_api_gateway_resource.provision.id
  http_method = aws_api_gateway_method.provision_post.http_method
  status_code = "200"
}

# ── Deployment ────────────────────────────────────────────────────────────────
resource "aws_api_gateway_deployment" "main" {
  rest_api_id = aws_api_gateway_rest_api.main.id

  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.provision,
      aws_api_gateway_method.provision_post,
      aws_api_gateway_integration.provision_lambda,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_api_gateway_integration.provision_lambda]
}

# ── Stage ─────────────────────────────────────────────────────────────────────
resource "aws_api_gateway_stage" "main" {
  deployment_id = aws_api_gateway_deployment.main.id
  rest_api_id   = aws_api_gateway_rest_api.main.id
  stage_name    = var.environment

  tags = var.tags
}
