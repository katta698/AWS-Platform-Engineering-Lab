# One tenant: a Lambda, a role, and the policy that is supposed to isolate it.
#
# Every tenant runs the same code against the same table. The only thing that
# separates them is this policy, which is why the policy is written out as
# literal JSON rather than assembled by aws_iam_policy_document. The condition
# block is the subject of the week and it should be readable here exactly as
# it is read by IAM -- a data source that renders to something slightly
# different would undermine the whole exercise.
#
# var.guard switches between the two policies the lab compares:
#
#   guard = true    The policy AWS documents.
#                     - Null on dynamodb:LeadingKeys, so a request that
#                       carries no partition key is refused instead of
#                       passing vacuously.
#                     - dynamodb:Select pinned to SPECIFIC_ATTRIBUTES, so a
#                       request with no ProjectionExpression is refused
#                       instead of returning every attribute.
#                     - no Scan.
#
#   guard = false   The same policy with both guards removed and Scan added.
#                   It reads as though it restricts the tenant. It does not.
#                   This is not a strawman: it is what you get by writing the
#                   obvious policy and testing it with GetItem only.

locals {
  table_arns = [var.table_arn, "${var.table_arn}/index/*"]

  read_actions = [
    "dynamodb:GetItem",
    "dynamodb:BatchGetItem",
    "dynamodb:Query",
  ]

  # Both variants scope to the tenant's own partition and to an attribute
  # allow-list. dynamodb:Attributes must name every key attribute of the
  # table or DynamoDB cannot perform the action at all.
  tenant_scope = {
    "dynamodb:LeadingKeys" = [var.tenant_id]
    "dynamodb:Attributes"  = var.allowed_attributes
  }

  # The DAX statement, identical in both policies. Note what is NOT in it:
  # any condition at all. dynamodb:LeadingKeys is not a valid condition key
  # for dax: actions, and once a request reaches the cluster the caller's
  # identity is gone -- the cluster's own service role decides what may be
  # read. Granting this is granting the whole table.
  dax_statement = {
    Sid    = "DaxAccessWhichIgnoresEverythingAbove"
    Effect = "Allow"
    Action = [
      "dax:GetItem",
      "dax:BatchGetItem",
      "dax:Query",
      "dax:Scan",
    ]
    Resource = [var.dax_cluster_arn]
  }

  # The two policies are built whole and one of them is chosen, rather than
  # one policy with conditional parts. Terraform requires both arms of a
  # conditional to have the same type, and these two deliberately do not --
  # the guarded one has two condition blocks the other lacks. Choosing
  # between the finished JSON strings sidesteps that, and has the better
  # property that each policy can be read end to end.

  guarded_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TenantScopedReads"
        Effect   = "Allow"
        Action   = local.read_actions
        Resource = local.table_arns
        Condition = {
          "ForAllValues:StringEquals" = local.tenant_scope

          # "A ForAllValues condition evaluates to true when the condition
          # key is not present in the request." Scan carries no LeadingKeys,
          # so without this the statement would grant every partition.
          "Null" = {
            "dynamodb:LeadingKeys" = "false"
          }

          # "If no ProjectionExpression is provided in the request, all
          # attributes will be returned regardless of any attribute
          # restrictions in the policy." This forces one to be provided.
          "StringEqualsIfExists" = {
            "dynamodb:Select" = "SPECIFIC_ATTRIBUTES"
          }
        }
      },
      local.dax_statement,
    ]
  })

  open_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TenantScopedReadsButNotReally"
        Effect   = "Allow"
        Action   = concat(local.read_actions, ["dynamodb:Scan"])
        Resource = local.table_arns
        Condition = {
          "ForAllValues:StringEquals" = local.tenant_scope
        }
      },
      local.dax_statement,
    ]
  })

  policy = var.guard ? local.guarded_policy : local.open_policy
}

resource "aws_iam_role" "this" {
  name = "${var.name_prefix}-${var.label}"

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

resource "aws_iam_role_policy" "data" {
  name   = "tenant-data-access"
  role   = aws_iam_role.this.id
  policy = local.policy
}

# Logs only. Deliberately not AWSLambdaVPCAccessExecutionRole-by-default:
# the EC2 network permissions are granted explicitly below so that what this
# role can do is visible in one place.
resource "aws_iam_role_policy" "runtime" {
  name = "lambda-runtime"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        # Required for Lambda to build the Hyperplane ENI that puts this
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

resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name_prefix}-${var.label}"
  retention_in_days = 7
  tags              = var.tags
}

resource "aws_lambda_function" "this" {
  function_name = "${var.name_prefix}-${var.label}"
  role          = aws_iam_role.this.arn
  handler       = "handler.handler"
  runtime       = "python3.13"
  timeout       = 30
  memory_size   = 512

  filename         = var.package_path
  source_code_hash = var.package_hash

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  environment {
    variables = {
      TABLE_NAME   = var.table_name
      TENANT_ID    = var.tenant_id
      DAX_ENDPOINT = var.dax_endpoint
    }
  }

  depends_on = [
    aws_iam_role_policy.runtime,
    aws_cloudwatch_log_group.this,
  ]

  tags = var.tags
}
