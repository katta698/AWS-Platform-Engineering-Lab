###############################################################################
# The two roles that define what the agent is allowed to be.
#
# This is the security surface of the whole week. An agent space is not a
# feature you enable -- it is a standing grant of visibility over an estate, and
# these two roles are where that grant is actually written down.
#
#   agentspace  what the agent may SEE and DO while investigating
#   operator    what the web app may do on behalf of a signed-in human
#
# Both trust the aidevops.amazonaws.com service principal, and both are
# constrained twice over: aws:SourceAccount pins the caller to this account, and
# aws:SourceArn pins it to an agent space ARN in this account and region. That
# pair is the confused-deputy guard -- without them, any agent space anywhere
# could ask AWS to assume these roles on someone else's behalf. Same reasoning
# as Week 15's bucket policy scoping CloudTrail by aws:SourceArn.
###############################################################################

###############################################################################
# Agent space role -- what the agent can see while investigating
###############################################################################

data "aws_iam_policy_document" "agentspace_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["aidevops.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    # Note the service namespace is `aidevops`, not `devops-agent`. The CLI, the
    # console and the docs all say "DevOps Agent"; IAM, ARNs and Service Quotas
    # all say `aidevops`. Getting this wrong produces a trust policy that looks
    # correct and never matches.
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:aidevops:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:agentspace/*"]
    }
  }
}

resource "aws_iam_role" "agentspace" {
  name               = "${local.name_prefix}-agentspace"
  description        = "Assumed by AWS DevOps Agent to investigate this account."
  assume_role_policy = data.aws_iam_policy_document.agentspace_assume.json
  tags               = local.tags
}

# AWS-managed, and deliberately not replaced with a hand-written policy.
#
# An investigating agent reads across a wide and moving surface -- logs, metrics,
# alarms, resource configuration, deployment history. Hand-rolling least
# privilege for that would produce a policy that is wrong within a release, and
# whose gaps show up as an investigation that quietly concludes nothing rather
# than as an access-denied error. The blast radius is bounded by the ASSOCIATION
# instead: the agent sees the accounts and resources that are associated with the
# space, and nothing else.
resource "aws_iam_role_policy_attachment" "agentspace_managed" {
  role       = aws_iam_role.agentspace.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsAgentAccessPolicy"
}

# Resource Explorer is how the agent discovers what exists. It needs its
# service-linked role to be creatable on first use.
resource "aws_iam_role_policy" "agentspace_resource_explorer_slr" {
  name = "resource-explorer-slr"
  role = aws_iam_role.agentspace.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "iam:CreateServiceLinkedRole"
        Resource = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/resource-explorer-2.amazonaws.com/*"
        Condition = {
          StringEquals = {
            "iam:AWSServiceName" = "resource-explorer-2.amazonaws.com"
          }
        }
      },
    ]
  })
}

###############################################################################
# Operator app role -- what the web UI may do for a signed-in human
###############################################################################

data "aws_iam_policy_document" "operator_assume" {
  statement {
    effect = "Allow"

    # sts:TagSession as well as sts:AssumeRole. The operator app tags the
    # session with the identity of the human driving it, which is what makes an
    # agent action attributable to a person rather than to "the agent".
    # Week 15 exists because unattributable actions are unanswerable.
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["aidevops.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:aidevops:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:agentspace/*"]
    }
  }
}

resource "aws_iam_role" "operator" {
  name               = "${local.name_prefix}-operator"
  description        = "Operator app role -- what the DevOps Agent web UI may do for a signed-in user."
  assume_role_policy = data.aws_iam_policy_document.operator_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "operator_managed" {
  role       = aws_iam_role.operator.name
  policy_arn = "arn:aws:iam::aws:policy/AIDevOpsOperatorAppAccessPolicy"
}

###############################################################################
# IAM propagation
#
# The DevOps Agent service VALIDATES the operator role's trust policy while
# creating the agent space. If IAM has not finished propagating, creation fails
# with a trust-policy error that reads like a misconfiguration rather than a
# timing problem -- and re-running succeeds with no changes, which is the
# signature of a race.
#
# AWS's own Terraform sample builds in a 30-second wait for exactly this. Copied
# deliberately rather than discovered the hard way.
###############################################################################

resource "time_sleep" "iam_propagation" {
  depends_on = [
    aws_iam_role_policy_attachment.agentspace_managed,
    aws_iam_role_policy_attachment.operator_managed,
    aws_iam_role_policy.agentspace_resource_explorer_slr,
  ]

  create_duration = "30s"
}
