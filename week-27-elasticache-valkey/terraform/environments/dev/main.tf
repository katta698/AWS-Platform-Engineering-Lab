# Week 27 -- what a cache actually costs.
#
# One ElastiCache Serverless cache for Valkey, and a Lambda that issues the
# same number of requests against three value sizes. ECPUs are billed on the
# higher of bytes moved or vCPU time, so identical request counts produce
# very different bills.
#
# The cache is VPC-only, so the client lives in the VPC with it. No NAT: the
# function talks to the cache and nothing else.
#
# Cost: $0.084/GB-hour on a 100 MB floor (~$0.0084/hour) plus $0.0023 per
# million ECPUs. No node meter.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "week-27-dev"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}

locals {
  name = "week27-valkey"

  tags = {
    Project = "AWS-Platform-Engineering-Lab"
    Week    = "27"
    Lab     = "elasticache-valkey"
  }
}

# Filter to real AZs. Names come back sorted, and a Local Zone like
# "us-east-1-dfw-1a" sorts before "us-east-1a", so "the first three" can pick
# one.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

# ---------------------------------------------------------------- network --

resource "aws_vpc" "main" {
  cidr_block           = "10.27.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = local.name }
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "${local.name}-private-${count.index}" }
}

resource "aws_security_group" "client" {
  name        = "${local.name}-client"
  description = "The load generator. Egress only."
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-client" }
}

resource "aws_security_group" "cache" {
  name        = "${local.name}-cache"
  description = "Valkey. Accepts the client only."
  vpc_id      = aws_vpc.main.id

  # 6379 is the primary endpoint. 6380 is the read-optimised reader endpoint
  # and is deliberately closed: this lab reads through the primary so the
  # measurement has one path.
  ingress {
    description     = "Valkey primary endpoint"
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.client.id]
  }

  tags = { Name = "${local.name}-cache" }
}

# ------------------------------------------------------------------ cache --

resource "aws_elasticache_serverless_cache" "valkey" {
  engine = "valkey"
  name   = local.name

  # A ceiling, not a reservation: serverless bills what is used, and these
  # cap a runaway. The 100 MB minimum billed storage applies regardless.
  cache_usage_limits {
    data_storage {
      maximum = 2
      unit    = "GB"
    }
    ecpu_per_second {
      maximum = 15000
    }
  }

  security_group_ids = [aws_security_group.cache.id]
  subnet_ids         = aws_subnet.private[*].id

  tags = { Name = local.name }
}

# --------------------------------------------------------------- function --

data "archive_file" "package" {
  type        = "zip"
  source_dir  = "${path.module}/build"
  output_path = "${path.module}/load_client.zip"
}

resource "aws_iam_role" "client" {
  name = "${local.name}-client"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "client" {
  name = "runtime"
  role = aws_iam_role.client.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        # Lambda needs these to build the ENI that puts it in the VPC.
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSubnets",
          "ec2:DeleteNetworkInterface",
          "ec2:AssignPrivateIpAddresses",
          "ec2:UnassignPrivateIpAddresses",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "client" {
  name              = "/aws/lambda/${local.name}-client"
  retention_in_days = 7
}

resource "aws_lambda_function" "client" {
  function_name = "${local.name}-client"
  role          = aws_iam_role.client.arn
  handler       = "handler.handler"
  runtime       = "python3.13"
  timeout       = 300
  memory_size   = 1024

  filename         = data.archive_file.package.output_path
  source_code_hash = data.archive_file.package.output_base64sha256

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.client.id]
  }

  environment {
    variables = {
      CACHE_HOST = aws_elasticache_serverless_cache.valkey.endpoint[0].address
      CACHE_PORT = aws_elasticache_serverless_cache.valkey.endpoint[0].port
    }
  }

  depends_on = [aws_iam_role_policy.client, aws_cloudwatch_log_group.client]
}
