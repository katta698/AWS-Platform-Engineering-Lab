# Week 26 -- tenant isolation on one pooled DynamoDB table, and the cache
# that removes it.
#
# One table partitioned by tenant_id. Three Lambda functions running the same
# code, separated only by their role's policy: alpha and beta carry the guards
# AWS documents, audit carries the same policy without them. All three also
# hold dax: permissions on the cluster, which is the point.
#
# The VPC exists only because DAX has no public endpoint. DynamoDB is reached
# from it by a gateway endpoint, which is free; a NAT gateway would be
# $0.045/hour. CloudWatch Logs needs neither.
#
# Cost: 3 x dax.t3.small at ~$0.04/node-hour, billing whether idle or not.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "week-26-dev"
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
  name = "week26-tenant-isolation"

  # DAX caps cluster_name at 20 chars, and the name reaches public
  # Certificate Transparency logs when encryption in transit is on. Keep it
  # short and non-identifying.
  dax_name = "week26-isolation"

  tags = {
    Project = "AWS-Platform-Engineering-Lab"
    Week    = "26"
    Lab     = "dynamodb-tenant-isolation"
  }

  # Must name every key attribute of the table, or DynamoDB cannot perform
  # the action. secret_note is deliberately absent: it is the attribute the
  # policy is trying to hide.
  allowed_attributes = ["tenant_id", "item_id", "description", "amount"]
}

# Filter to real AZs. Names come back sorted, and a Local Zone like
# "us-east-1-dfw-1a" sorts before "us-east-1a", so "the first three" can pick
# one; DAX then rejects it with SubnetNotAllowedFault.
data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

# ---------------------------------------------------------------- network --

resource "aws_vpc" "main" {
  cidr_block           = "10.26.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = local.name }
}

# Three subnets in three AZs. DAX places one node per subnet, and three nodes
# in three AZs is the smallest fault-tolerant cluster: "Three nodes are
# required for a DAX cluster to be fault-tolerant."
resource "aws_subnet" "private" {
  count = 3

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = { Name = "${local.name}-private-${count.index}" }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.name}-private" }
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Free, and the only way these functions reach DynamoDB directly once they
# are attached to the VPC. Without it the "direct" path times out and the
# comparison the lab is built on cannot be made.
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = { Name = "${local.name}-dynamodb" }
}

resource "aws_security_group" "lambda" {
  name        = "${local.name}-lambda"
  description = "Tenant functions. Egress only."
  vpc_id      = aws_vpc.main.id

  egress {
    description = "To DAX and to the DynamoDB gateway endpoint"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-lambda" }
}

resource "aws_security_group" "dax" {
  name        = "${local.name}-dax"
  description = "DAX cluster. Accepts the DAX protocol from the functions only."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "DAX unencrypted cluster protocol"
    from_port       = 8111
    to_port         = 8111
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  ingress {
    description     = "DAX encrypted cluster protocol"
    from_port       = 9111
    to_port         = 9111
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-dax" }
}

# ------------------------------------------------------------------ table --

resource "aws_dynamodb_table" "pool" {
  name         = "${local.name}-pool"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "tenant_id"
  range_key    = "item_id"

  attribute {
    name = "tenant_id"
    type = "S"
  }

  attribute {
    name = "item_id"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  point_in_time_recovery {
    enabled = false # a lab table rebuilt by a script; PITR would be cost without purpose
  }

  tags = { Name = "${local.name}-pool" }
}

# -------------------------------------------------------------------- DAX --

# The cluster's own role. Everything that reaches DynamoDB through DAX is
# authorised by THIS policy and nothing else -- "the only access controls
# that are in effect are the permissions in the DAX cluster's IAM policy."
# It is scoped to the table and that is as far as it can be scoped: there is
# no tenant here to scope to, because by this point the caller's identity is
# gone.
resource "aws_iam_role" "dax" {
  name = "${local.name}-dax-service"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "dax.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "dax" {
  name = "dax-table-access"
  role = aws_iam_role.dax.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DaxAccessPolicy"
      Effect = "Allow"
      Action = [
        "dynamodb:DescribeTable",
        "dynamodb:GetItem",
        "dynamodb:BatchGetItem",
        "dynamodb:Query",
        "dynamodb:Scan",
      ]
      Resource = [aws_dynamodb_table.pool.arn]
    }]
  })
}

resource "aws_dax_subnet_group" "main" {
  name       = local.dax_name
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_dax_cluster" "main" {
  cluster_name       = local.dax_name
  iam_role_arn       = aws_iam_role.dax.arn
  node_type          = var.dax_node_type
  replication_factor = var.dax_nodes

  subnet_group_name  = aws_dax_subnet_group.main.name
  security_group_ids = [aws_security_group.dax.id]

  # The whole point is a cache hit, so give it a TTL long enough that the
  # second read is served from the cache rather than re-fetched.
  parameter_group_name = aws_dax_parameter_group.main.name

  server_side_encryption {
    enabled = true
  }

  tags = { Name = local.dax_name }
}

resource "aws_dax_parameter_group" "main" {
  name = local.dax_name

  parameters {
    name  = "query-ttl-millis"
    value = "300000"
  }

  parameters {
    name  = "record-ttl-millis"
    value = "300000"
  }
}

# --------------------------------------------------------------- function --


# Three principals, running identical code, separated only by the policy on
# their execution role.
#
# for_each rather than a child module: a remote HCP run uploads only the root
# module directory, so ../../modules is absent at plan time.
locals {
  principals = {
    # The policy AWS documents.
    alpha = { tenant = "tenant-alpha", guard = true }
    beta  = { tenant = "tenant-beta", guard = true }

    # Same tenant as alpha. Same policy with both guards removed and Scan
    # added -- what you get by writing the obvious thing and testing it with
    # GetItem. Everything it can do that alpha cannot is the consequence of
    # two missing condition blocks.
    audit = { tenant = "tenant-alpha", guard = false }
  }

  package_path = "${path.module}/tenant_api.zip"
  table_arns   = [aws_dynamodb_table.pool.arn, "${aws_dynamodb_table.pool.arn}/index/*"]

  read_actions = [
    "dynamodb:GetItem",
    "dynamodb:BatchGetItem",
    "dynamodb:Query",
  ]

  # The DAX statement, identical for all three. Note what is NOT in it: any
  # condition at all. dynamodb:LeadingKeys is not a valid condition key for
  # dax: actions, and once a request reaches the cluster the caller's identity
  # is gone -- the cluster's own service role decides what may be read.
  # Granting this is granting the whole table.
  dax_statement = {
    Sid      = "DaxAccessWhichIgnoresEverythingAbove"
    Effect   = "Allow"
    Action   = ["dax:GetItem", "dax:BatchGetItem", "dax:Query", "dax:Scan"]
    Resource = [aws_dax_cluster.main.arn]
  }

  # Two whole policies, one chosen per principal: a Terraform conditional
  # needs both arms to share a type, and these deliberately do not.
  guarded_policies = {
    for k, v in local.principals : k => jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "TenantScopedReads"
          Effect   = "Allow"
          Action   = local.read_actions
          Resource = local.table_arns
          Condition = {
            "ForAllValues:StringEquals" = {
              "dynamodb:LeadingKeys" = [v.tenant]
              "dynamodb:Attributes"  = local.allowed_attributes
            }

            # "A ForAllValues condition evaluates to true when the condition
            # key is not present in the request." Scan carries no
            # LeadingKeys, so without this the statement grants every
            # partition.
            "Null" = { "dynamodb:LeadingKeys" = "false" }

            # "If no ProjectionExpression is provided in the request, all
            # attributes will be returned regardless of any attribute
            # restrictions in the policy." This forces one to be provided.
            "StringEqualsIfExists" = { "dynamodb:Select" = "SPECIFIC_ATTRIBUTES" }
          }
        },
        local.dax_statement,
      ]
    })
  }

  open_policies = {
    for k, v in local.principals : k => jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid      = "TenantScopedReadsButNotReally"
          Effect   = "Allow"
          Action   = concat(local.read_actions, ["dynamodb:Scan"])
          Resource = local.table_arns
          Condition = {
            "ForAllValues:StringEquals" = {
              "dynamodb:LeadingKeys" = [v.tenant]
              "dynamodb:Attributes"  = local.allowed_attributes
            }
          }
        },
        local.dax_statement,
      ]
    })
  }

  policies = {
    for k, v in local.principals :
    k => v.guard ? local.guarded_policies[k] : local.open_policies[k]
  }
}

resource "aws_iam_role" "tenant" {
  for_each = local.principals

  name = "${local.name}-${each.key}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "tenant_data" {
  for_each = local.principals

  name   = "tenant-data-access"
  role   = aws_iam_role.tenant[each.key].id
  policy = local.policies[each.key]
}

resource "aws_iam_role_policy" "tenant_runtime" {
  for_each = local.principals

  name = "lambda-runtime"
  role = aws_iam_role.tenant[each.key].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        # Required for Lambda to build the Hyperplane ENI that puts the
        # function in the VPC. Without a VPC it cannot reach DAX at all.
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

resource "aws_cloudwatch_log_group" "tenant" {
  for_each = local.principals

  name              = "/aws/lambda/${local.name}-${each.key}"
  retention_in_days = 7
}

resource "aws_lambda_function" "tenant" {
  for_each = local.principals

  function_name = "${local.name}-${each.key}"
  role          = aws_iam_role.tenant[each.key].arn
  handler       = "handler.handler"
  runtime       = "python3.13"
  timeout       = 30
  memory_size   = 512

  filename         = local.package_path
  source_code_hash = filebase64sha256(local.package_path)

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      TABLE_NAME   = aws_dynamodb_table.pool.name
      TENANT_ID    = each.value.tenant
      DAX_ENDPOINT = aws_dax_cluster.main.cluster_address
    }
  }

  depends_on = [
    aws_iam_role_policy.tenant_runtime,
    aws_cloudwatch_log_group.tenant,
  ]
}
