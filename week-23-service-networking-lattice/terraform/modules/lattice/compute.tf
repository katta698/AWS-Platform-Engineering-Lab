# ---------------------------------------------------------------------------
# The two callers and the service behind them
# ---------------------------------------------------------------------------

data "archive_file" "backend" {
  type        = "zip"
  source_dir  = "${var.lambda_dir}/backend"
  output_path = "${path.module}/builds/backend.zip"
  excludes    = ["__pycache__", "*.pyc", "*.pyo"]
}

data "archive_file" "client" {
  type        = "zip"
  source_dir  = "${var.lambda_dir}/client"
  output_path = "${path.module}/builds/client.zip"
  excludes    = ["__pycache__", "*.pyc", "*.pyo"]
}

# ---- the service being protected ------------------------------------------

resource "aws_iam_role" "backend" {
  name = "${var.name}-backend"

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

resource "aws_cloudwatch_log_group" "backend" {
  name              = "/aws/lambda/${var.name}-backend"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_iam_role_policy" "backend_logs" {
  name = "logs"
  role = aws_iam_role.backend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "${aws_cloudwatch_log_group.backend.arn}:*"
    }]
  })
}

resource "aws_lambda_function" "backend" {
  function_name = "${var.name}-backend"
  role          = aws_iam_role.backend.arn
  handler       = "handler.handler"
  runtime       = "python3.13"
  timeout       = 10

  filename         = data.archive_file.backend.output_path
  source_code_hash = data.archive_file.backend.output_base64sha256

  depends_on = [aws_cloudwatch_log_group.backend]
  tags       = var.tags
}

resource "aws_lambda_permission" "lattice" {
  statement_id  = "AllowVpcLattice"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.backend.function_name
  principal     = "vpc-lattice.amazonaws.com"
  source_arn    = aws_vpclattice_target_group.backend.arn
}

# ---- the allowed caller ----------------------------------------------------

resource "aws_iam_role" "client" {
  name = "${var.name}-orders-client"

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

# ---- the caller that must be refused ---------------------------------------
#
# Assumable by the client function, so one function can call as either identity.
# Nothing else differs: same VPC, same subnet, same security group.
resource "aws_iam_role" "stranger" {
  name = "${var.name}-stranger"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_role.client.arn }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "client" {
  name              = "/aws/lambda/${var.name}-client"
  retention_in_days = 7
  tags              = var.tags
}

# Note what is NOT here: no vpc-lattice-svcs:Invoke grant.
#
# Authorisation needs an explicit allow from BOTH sides -- the auth policy on
# the resource AND an identity policy on the caller. Leaving this out is how
# you discover that, and it is why test 2 is the first thing that must pass.
resource "aws_iam_role_policy" "client" {
  name = "run"
  role = aws_iam_role.client.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Logs"
        Effect = "Allow"
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = [
          "${aws_cloudwatch_log_group.client.arn}:*",
        ]
      },
      {
        Sid      = "Eni"
        Effect   = "Allow"
        Action   = ["ec2:CreateNetworkInterface", "ec2:DescribeNetworkInterfaces", "ec2:DeleteNetworkInterface"]
        Resource = "*" # the VPC-attached Lambda ENI lifecycle has no scopable resource
      },
      {
        Sid      = "CallTheService"
        Effect   = "Allow"
        Action   = "vpc-lattice-svcs:Invoke"
        Resource = "${aws_vpclattice_service.rates.arn}/*"
      },
      {
        Sid      = "BecomeTheStranger"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = aws_iam_role.stranger.arn
      },
    ]
  })
}

# The stranger is allowed by IAM to invoke, so a denial proves the AUTH POLICY
# refused it rather than the identity policy. Without this the test would pass
# for the wrong reason.
resource "aws_iam_role_policy" "stranger" {
  name = "run"
  role = aws_iam_role.stranger.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "vpc-lattice-svcs:Invoke"
      Resource = "${aws_vpclattice_service.rates.arn}/*"
    }]
  })
}

resource "aws_lambda_function" "client" {
  function_name = "${var.name}-client"
  role          = aws_iam_role.client.arn
  handler       = "handler.handler"
  runtime       = "python3.13"
  timeout       = 30

  filename         = data.archive_file.client.output_path
  source_code_hash = data.archive_file.client.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.consumer[*].id
    security_group_ids = [aws_security_group.client.id]
  }

  environment {
    variables = {
      SERVICE_URL   = "http://${aws_vpclattice_service.rates.dns_entry[0].domain_name}"
      STRANGER_ROLE = aws_iam_role.stranger.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.client]
  tags       = var.tags
}
