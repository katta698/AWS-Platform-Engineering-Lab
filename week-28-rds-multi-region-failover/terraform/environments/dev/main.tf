# Week 28 -- a failover that has actually been run.
#
# A Postgres primary in us-east-1, a cross-region read replica in us-west-2,
# and the failover runbook declared as an ARC Region switch plan rather than
# written in a wiki.
#
# Promotion is irreversible: the replica becomes a standalone instance and
# replication stops for good. That is why nobody rehearses it, and why the
# measurement is worth taking.
#
# Cost: two db.t4g.micro at $0.016/hr, storage $0.125/GB-month, and the
# Region switch plan at $70/month prorated -- proration granularity is
# undocumented, so the figure comes from the bill.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      # rds_promote_read_replica_config landed in 6.47.0.
      source  = "hashicorp/aws"
      version = ">= 6.47, < 7.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }

  cloud {
    organization = "Katta"

    workspaces {
      name = "week-28-dev"
    }
  }
}

provider "aws" {
  region = var.primary_region

  default_tags {
    tags = local.tags
  }
}

# A cross-region replica is a resource in the other region, so it needs its
# own provider. Nothing else this week is two-region.
provider "aws" {
  alias  = "replica"
  region = var.replica_region

  default_tags {
    tags = local.tags
  }
}

locals {
  name = "week28-failover"

  tags = {
    Project = "AWS-Platform-Engineering-Lab"
    Week    = "28"
  }
}

# ── Network: the default VPC in each region ─────────────────────────────────
#
# Nothing here needs a custom VPC, and a NAT gateway would cost more per hour
# than both databases together.

data "aws_vpc" "primary" {
  default = true
}

data "aws_vpc" "replica" {
  provider = aws.replica
  default  = true
}

# Local Zones sort ahead of regular AZs -- us-east-1-dfw-1a precedes
# us-east-1a because "-" precedes "a" -- and a DB subnet group rejects a
# Local Zone subnet. Filter on zone type rather than taking the first three.
data "aws_availability_zones" "primary" {
  state = "available"

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

data "aws_availability_zones" "replica" {
  provider = aws.replica
  state    = "available"

  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

data "aws_subnets" "primary" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  filter {
    name   = "availability-zone"
    values = data.aws_availability_zones.primary.names
  }
}

data "aws_subnets" "replica" {
  provider = aws.replica

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.replica.id]
  }

  filter {
    name   = "availability-zone"
    values = data.aws_availability_zones.replica.names
  }
}

resource "aws_db_subnet_group" "primary" {
  name       = "${local.name}-primary"
  subnet_ids = data.aws_subnets.primary.ids
}

resource "aws_db_subnet_group" "replica" {
  provider   = aws.replica
  name       = "${local.name}-replica"
  subnet_ids = data.aws_subnets.replica.ids
}

# ── Security groups ─────────────────────────────────────────────────────────

resource "aws_security_group" "db_primary" {
  name        = "${local.name}-db"
  description = "Postgres, reachable only from the writer function"
  vpc_id      = data.aws_vpc.primary.id
}

resource "aws_vpc_security_group_ingress_rule" "db_from_writer" {
  security_group_id            = aws_security_group.db_primary.id
  referenced_security_group_id = aws_security_group.writer.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Postgres from the writer function only"
}

# The replica needs a group in its own region. No client runs there, so it
# has no ingress at all -- replication arrives over the managed path, not
# through this group.
resource "aws_security_group" "db_replica" {
  provider    = aws.replica
  name        = "${local.name}-db"
  description = "Replica: no client ingress, replication is managed"
  vpc_id      = data.aws_vpc.replica.id
}

resource "aws_security_group" "writer" {
  name        = "${local.name}-writer"
  description = "The function generating write load"
  vpc_id      = data.aws_vpc.primary.id
}

resource "aws_vpc_security_group_egress_rule" "writer_to_db" {
  security_group_id            = aws_security_group.writer.id
  referenced_security_group_id = aws_security_group.db_primary.id
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "Only the database. No NAT, no internet."
}

# ── The databases ───────────────────────────────────────────────────────────

resource "random_password" "db" {
  length  = 32
  special = false
}

resource "aws_db_instance" "primary" {
  identifier     = "${local.name}-primary"
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = "db.t4g.micro"

  allocated_storage = 20
  storage_type      = "gp2"
  storage_encrypted = true

  db_name  = "lab"
  username = "labadmin"
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [aws_security_group.db_primary.id]
  publicly_accessible    = false

  # A read replica cannot be created from a source with backups disabled.
  # This is not a durability preference; it is a prerequisite.
  backup_retention_period = 1

  apply_immediately   = true
  skip_final_snapshot = true
}

resource "aws_db_instance" "replica" {
  provider   = aws.replica
  identifier = "${local.name}-replica"

  # Cross-region replication takes the full ARN. A bare identifier only works
  # within one region.
  replicate_source_db = aws_db_instance.primary.arn
  instance_class      = "db.t4g.micro"

  # An encrypted source replicated across regions needs a key that exists in
  # the DESTINATION region. The source's key is not reachable from here, and
  # omitting this is the usual first-apply failure.
  kms_key_id = data.aws_kms_alias.rds_replica.target_key_arn

  # Declare this even though RDS sets it on its own: a replica of an encrypted
  # source comes up encrypted, so AWS reports true while the config says null,
  # and "true -> null forces replacement" destroys the database on the NEXT
  # apply. The first apply succeeds either way, which is what makes it a trap.
  storage_encrypted = true

  db_subnet_group_name   = aws_db_subnet_group.replica.name
  vpc_security_group_ids = [aws_security_group.db_replica.id]
  publicly_accessible    = false

  # ReplicaLag is a standard RDS metric, published to CloudWatch every 60s
  # without being asked. Enhanced Monitoring is OS metrics to CloudWatch
  # Logs and would only add ingestion cost.
  apply_immediately   = true
  skip_final_snapshot = true
}

data "aws_kms_alias" "rds_replica" {
  provider = aws.replica
  name     = "alias/aws/rds"
}

# ── The failover runbook, as code ───────────────────────────────────────────

resource "aws_iam_role" "arc" {
  name = "${local.name}-arc-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "arc-region-switch.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "arc" {
  name = "rds-promote"
  role = aws_iam_role.arc.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "rds:DescribeDBInstances",
        "rds:PromoteReadReplica",
        "rds:CreateDBInstanceReadReplica",
        "rds:ModifyDBInstance",

        # Not in AWS's sample policy for the RDS execution block, and the plan
        # sits at "Action required" without it: Region switch pre-flights the
        # role against each step, and when it cannot simulate it reports both
        # a missing-policy warning and "does not have data on DB instance".
        # One permission, two warnings that read like unrelated problems.
        "iam:SimulatePrincipalPolicy",

        # The ManualApproval step needs the role to be able to approve it.
        # Surfaced only after the simulate permission was granted -- the
        # evaluator reports what it can currently see, so the warnings arrive
        # one layer at a time rather than all at once.
        "arc-region-switch:ApprovePlanExecutionStep",
      ]
      Resource = "*"
    }]
  })
}

# $70 per plan per month, prorated. Every other resource this week is cents,
# so this one is switchable.
resource "aws_arcregionswitch_plan" "failover" {
  count = var.create_region_switch_plan ? 1 : 0

  name              = local.name
  description       = "Promote the us-west-2 Postgres replica to primary"
  execution_role    = aws_iam_role.arc.arn
  recovery_approach = "activePassive"
  regions           = [var.primary_region, var.replica_region]
  primary_region    = var.primary_region

  # Declared us-east-1 first to match the order GetPlan returns. The provider
  # compares workflows by position, so the reverse order makes every plan show
  # the two workflows swapping places -- and the first apply fail outright with
  # "block count changed from 0 to 1".
  #
  # Every region in an activePassive plan needs its own ACTIVATE workflow.
  # Two API rejections pin the shape down, and the provider's own example
  # satisfies neither:
  #   "activePassive plans must not specify target action 'deactivate'"
  #   "must have activate workflows defined for each region but found
  #    workflow for only us-west-2"
  #
  # Activating us-east-1 is the failback direction, and there is nothing to
  # automate there: the promoted instance in us-west-2 is now a standalone
  # primary, so coming back means building a new replica and promoting it.
  # An approval step says that out loud rather than implying a button exists.
  workflow {
    workflow_target_action = "activate"
    workflow_target_region = var.primary_region

    step {
      name                 = "failback-is-not-a-button"
      execution_block_type = "ManualApproval"

      execution_approval_config {
        approval_role   = aws_iam_role.arc.arn
        timeout_minutes = 60
      }
    }
  }

  workflow {
    workflow_target_action = "activate"
    workflow_target_region = var.replica_region

    step {
      name                 = "promote-replica"
      execution_block_type = "RdsPromoteReadReplica"

      rds_promote_read_replica_config {
        db_instance_arn_map = {
          (var.primary_region) = aws_db_instance.primary.arn
          (var.replica_region) = aws_db_instance.replica.arn
        }
        timeout_minutes = 30
      }
    }
  }
}

# ── Write load, so replication lag is something other than zero ────────────
#
# A Lambda rather than anything longer-lived: the work is a few thousand
# INSERTs on demand, stateless, one invocation at a time. Nothing here runs
# between runs, so paying for an always-on writer would buy nothing. An ECS
# task or an EC2 instance would be the right shape only if the load had to be
# sustained for hours or needed more than one concurrent writer.

data "archive_file" "writer" {
  type        = "zip"
  source_dir  = "${path.module}/build"
  output_path = "${path.module}/writer.zip"
}

resource "aws_iam_role" "writer" {
  name = "${local.name}-writer"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "writer" {
  name = "runtime"
  role = aws_iam_role.writer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = "arn:aws:logs:*:*:*"
    }]
  })
}

# An in-VPC function needs this to create its own network interfaces. Without
# it the function is created and every invocation fails on ENI setup.
resource "aws_iam_role_policy_attachment" "writer_vpc" {
  role       = aws_iam_role.writer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_function" "writer" {
  function_name = "${local.name}-writer"
  role          = aws_iam_role.writer.arn
  handler       = "handler.handler"
  runtime       = "python3.13"
  timeout       = 300
  memory_size   = 512

  filename         = data.archive_file.writer.output_path
  source_code_hash = data.archive_file.writer.output_base64sha256

  vpc_config {
    subnet_ids         = data.aws_subnets.primary.ids
    security_group_ids = [aws_security_group.writer.id]
  }

  environment {
    variables = {
      DB_HOST = aws_db_instance.primary.address
      DB_NAME = aws_db_instance.primary.db_name
      DB_USER = aws_db_instance.primary.username
      DB_PASS = random_password.db.result
    }
  }
}
