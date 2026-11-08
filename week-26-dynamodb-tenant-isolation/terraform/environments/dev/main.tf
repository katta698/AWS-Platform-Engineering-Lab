# Week 26 -- tenant isolation on one pooled DynamoDB table, and the cache
# that quietly removes it.
#
# THE SHAPE
# ---------
# One table. Items partitioned by tenant_id. Three Lambda functions running
# identical code, separated only by the IAM policy on their execution role:
#
#   alpha   scoped to tenant-alpha, with the guards AWS documents
#   beta    scoped to tenant-beta,  with the same guards
#   audit   scoped to tenant-alpha, with the guards removed -- the policy you
#           get by writing the obvious thing and testing it with GetItem
#
# All three also hold dax: permissions on the cluster, because that is what a
# team adds when the read latency becomes a problem. That grant is what the
# week is about.
#
# WHY THERE IS A VPC HERE AT ALL
# ------------------------------
# DAX has no public endpoint. "Access to DAX cluster nodes is restricted to
# applications running on Amazon EC2 instances within an Amazon VPC
# environment", and a cluster must be given a subnet group at creation. So
# the functions have to be attached to a VPC to reach it, and once they are,
# they lose the default route to the public DynamoDB endpoint too.
#
# That is solved with a GATEWAY endpoint for DynamoDB, which is free, rather
# than a NAT gateway at $0.045/hour or interface endpoints at $0.01/hour per
# AZ. CloudWatch Logs needs neither: log delivery is performed by the Lambda
# service from the Lambda-managed VPC, which is unaffected by attaching the
# function to this one.
#
# COST
# ----
# DAX is the only meaningful line and it bills per node-hour whether or not
# anything reads from it: 3 x dax.t3.small at ~$0.04/hour is ~$0.12/hour, or
# ~$2.88/day. Everything else here is on-demand and the lab's volume is a few
# hundred requests. Destroy when done; this is not a week to leave running.

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

  # DAX caps cluster_name at 20 characters, which local.name exceeds, so the
  # cluster carries a shorter name of its own rather than everything being
  # shortened to suit one resource.
  #
  # Keep it non-identifying: enabling encryption in transit makes ACM issue a
  # certificate carrying the cluster name, and ACM records every public
  # certificate in Certificate Transparency logs. AWS: "do not include
  # sensitive identifying information, such as your customers' account
  # numbers, in the cluster name."
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

data "aws_availability_zones" "available" {
  state = "available"
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

# Built by scripts/build_lambda.sh, which pip-installs amazon-dax-client into
# build/. The DAX client is not in the Lambda runtime and the DAX path cannot
# work without it.
data "archive_file" "package" {
  type        = "zip"
  source_dir  = "${path.module}/../../../build/package"
  output_path = "${path.module}/../../../build/tenant_api.zip"
}

module "alpha" {
  source = "../../modules/tenant"

  name_prefix        = local.name
  label              = "alpha"
  tenant_id          = "tenant-alpha"
  guard              = true
  allowed_attributes = local.allowed_attributes

  table_name      = aws_dynamodb_table.pool.name
  table_arn       = aws_dynamodb_table.pool.arn
  dax_cluster_arn = aws_dax_cluster.main.arn
  dax_endpoint    = aws_dax_cluster.main.cluster_address

  package_path       = data.archive_file.package.output_path
  package_hash       = data.archive_file.package.output_base64sha256
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.lambda.id]
  tags               = local.tags
}

module "beta" {
  source = "../../modules/tenant"

  name_prefix        = local.name
  label              = "beta"
  tenant_id          = "tenant-beta"
  guard              = true
  allowed_attributes = local.allowed_attributes

  table_name      = aws_dynamodb_table.pool.name
  table_arn       = aws_dynamodb_table.pool.arn
  dax_cluster_arn = aws_dax_cluster.main.arn
  dax_endpoint    = aws_dax_cluster.main.cluster_address

  package_path       = data.archive_file.package.output_path
  package_hash       = data.archive_file.package.output_base64sha256
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.lambda.id]
  tags               = local.tags
}

# Same tenant as alpha, policy without the guards. Everything it can do that
# alpha cannot is a consequence of two missing condition blocks.
module "audit" {
  source = "../../modules/tenant"

  name_prefix        = local.name
  label              = "audit"
  tenant_id          = "tenant-alpha"
  guard              = false
  allowed_attributes = local.allowed_attributes

  table_name      = aws_dynamodb_table.pool.name
  table_arn       = aws_dynamodb_table.pool.arn
  dax_cluster_arn = aws_dax_cluster.main.arn
  dax_endpoint    = aws_dax_cluster.main.cluster_address

  package_path       = data.archive_file.package.output_path
  package_hash       = data.archive_file.package.output_base64sha256
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.lambda.id]
  tags               = local.tags
}
