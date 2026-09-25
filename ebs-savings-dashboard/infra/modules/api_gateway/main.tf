resource "aws_cloudwatch_log_group" "api_gw" {
  name              = "/aws/apigateway/${var.prefix}-ebs-savings"
  retention_in_days = 14
}

resource "aws_apigatewayv2_api" "ebs" {
  name          = "${var.prefix}-ebs-savings"
  protocol_type = "HTTP"
  description   = "EBS Savings Dashboard API"

  cors_configuration {
    allow_origins = [var.allowed_origin]
    allow_methods = ["GET", "OPTIONS"]
    allow_headers = ["Authorization", "Content-Type"]
    max_age       = 300
  }
}

# ── JWT authorizer (Cognito) — created only when use_cognito = true ────────────
resource "aws_apigatewayv2_authorizer" "cognito" {
  count            = var.use_cognito ? 1 : 0
  api_id           = aws_apigatewayv2_api.ebs.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "cognito"

  jwt_configuration {
    audience = [var.cognito_app_client_id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${var.cognito_user_pool_id}"
  }
}

# ── Lambda integration ────────────────────────────────────────────────────────
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.ebs.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.lambda_function_arn
  payload_format_version = "2.0"
}

# ── Routes ────────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_route" "ebs_savings" {
  api_id             = aws_apigatewayv2_api.ebs.id
  route_key          = "GET /ebs-savings"
  authorization_type = var.use_cognito ? "JWT" : "NONE"
  authorizer_id      = var.use_cognito ? aws_apigatewayv2_authorizer.cognito[0].id : null
  target             = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# ── Stage ─────────────────────────────────────────────────────────────────────
resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.ebs.id
  name        = "prod"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit   = 50
    throttling_rate_limit    = 10
    detailed_metrics_enabled = true
    logging_level            = "INFO"
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api_gw.arn
    format          = jsonencode({ requestId = "$context.requestId", routeKey = "$context.routeKey", status = "$context.status", integrationError = "$context.integrationErrorMessage" })
  }
}

# ── Allow API Gateway to invoke Lambda ───────────────────────────────────────
resource "aws_lambda_permission" "api_gw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.lambda_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.ebs.execution_arn}/*/*"
}
