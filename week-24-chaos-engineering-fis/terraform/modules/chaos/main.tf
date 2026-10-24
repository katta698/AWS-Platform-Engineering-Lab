# The faults, and the safety net that is supposed to stop them.
#
# WHY ONLY aws:ecs:stop-task
# --------------------------
# FIS has richer ECS actions -- task-cpu-stress, task-network-latency,
# task-io-stress and others -- but every aws:ecs:task-* action requires the
# tasks to be MANAGED BY SYSTEMS MANAGER, which on Fargate means adding an SSM
# agent sidecar to the task definition. aws:ecs:stop-task goes through the ECS
# API and needs nothing.
#
# That is a real prerequisite and worth knowing before planning a chaos day:
# the interesting-sounding actions need a change to every task definition you
# want to experiment on. This week measures stop-condition latency, for which
# stopping tasks is a sufficient and honest fault.
#
# THREE EXPERIMENTS, ONE QUESTION
# -------------------------------
#   1  recovery      no stop condition. How long does ECS take to come back?
#   2  net-fast      stop condition on the 60s alarm
#   3  net-typical   stop condition on the 300s/2-datapoint alarm
#
# 2 and 3 inject the SAME fault for the SAME duration. The only difference is
# which alarm is wired in as the safety net, so the difference in how long the
# damage ran is attributable to the alarm and nothing else.

data "aws_iam_policy_document" "fis_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["fis.amazonaws.com"]
    }
    # Confused-deputy guards. FIS assumes this role on your behalf, so the
    # trust policy is scoped to this account and this experiment template
    # rather than to the service at large.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [var.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:fis:${var.region}:${var.account_id}:experiment/*"]
    }
  }
}

resource "aws_iam_role" "fis" {
  name               = "${var.name}-fis"
  assume_role_policy = data.aws_iam_policy_document.fis_assume.json
  tags               = var.tags
}

# Exactly the permissions aws:ecs:stop-task needs, and nothing else. FIS cannot
# break what the role cannot reach -- which is the first line of containment,
# before any stop condition is involved.
data "aws_iam_policy_document" "fis" {
  statement {
    sid       = "DescribeTheCluster"
    actions   = ["ecs:ListTasks", "ecs:DescribeTasks", "ecs:DescribeClusters"]
    resources = ["*"]
  }
  statement {
    sid     = "StopTasksInThisClusterOnly"
    actions = ["ecs:StopTask"]
    resources = [
      "arn:aws:ecs:${var.region}:${var.account_id}:task/${var.cluster_name}/*"
    ]
  }
  statement {
    sid       = "ReadTheStopConditionAlarms"
    actions   = ["cloudwatch:DescribeAlarms"]
    resources = ["*"]
  }
  # FIS does not write experiment logs the way an application does. It sets up
  # a VENDED LOG DELIVERY, which needs the logs:*LogDelivery family and the
  # ability to put a resource policy on the destination log group -- not the
  # CreateLogStream/PutLogEvents pair you would reach for by instinct.
  #
  # Getting this wrong fails the experiment at START, before any fault is
  # injected, with "does not have sufficient privileges to perform
  # logs:CreateLogDelivery". Clear once you read it, and invisible until you
  # run one.
  #
  # The delivery actions do not accept a resource ARN -- they are account-level
  # operations, so "*" is required rather than lax. The log group itself is
  # still pinned on the statement below.
  statement {
    sid = "SetUpVendedLogDelivery"
    actions = [
      "logs:CreateLogDelivery",
      "logs:GetLogDelivery",
      "logs:UpdateLogDelivery",
      "logs:DeleteLogDelivery",
      "logs:ListLogDeliveries",
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
      # PutResourcePolicy is ACCOUNT-level. Scoping it to the log group ARN
      # looks tighter and simply does not work: the second attempt failed with
      # "does not have sufficient privileges to set up logging for the
      # specified CloudWatch LogGroup", which is the same wall wearing a
      # different hat.
      "logs:PutResourcePolicy",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "WriteIntoThisLogGroupOnly"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:PutRetentionPolicy"]
    resources = ["${aws_cloudwatch_log_group.fis.arn}:*"]
  }
}

resource "aws_iam_role_policy" "fis" {
  name   = "${var.name}-fis"
  role   = aws_iam_role.fis.id
  policy = data.aws_iam_policy_document.fis.json
}

resource "aws_cloudwatch_log_group" "fis" {
  name              = "/fis/${var.name}"
  retention_in_days = 1
  tags              = var.tags
}

locals {
  # The target selects by cluster and takes a percentage, so the same template
  # works whatever the desired count happens to be.
  common_target = {
    resource_type  = "aws:ecs:task"
    selection_mode = "PERCENT(${var.fault_percent})"
  }
}

# ---------------------------------------------------------------------------
# 1. Recovery. No stop condition at all.
#
# Deliberately unguarded: the point is to see the unassisted recovery curve,
# which is the baseline every later number is measured against. Safe because
# the blast radius is one lab service and the action reverts by itself -- ECS
# replaces the tasks whether or not anyone intervenes.
# ---------------------------------------------------------------------------
resource "aws_fis_experiment_template" "recovery" {
  description = "Stop ${var.fault_percent}% of tasks, no stop condition. Measures unassisted recovery."
  role_arn    = aws_iam_role.fis.arn

  stop_condition {
    source = "none"
  }

  target {
    name           = "tasks"
    resource_type  = local.common_target.resource_type
    selection_mode = local.common_target.selection_mode

    resource_tag {
      key   = "FISTarget"
      value = var.name
    }

    parameters = {
      cluster = var.cluster_name
      service = var.service_name
    }
  }

  action {
    name      = "stop-tasks"
    action_id = "aws:ecs:stop-task"
    target {
      key   = "Tasks"
      value = "tasks"
    }
  }

  log_configuration {
    log_schema_version = 2
    cloudwatch_logs_configuration {
      log_group_arn = "${aws_cloudwatch_log_group.fis.arn}:*"
    }
  }

  tags = merge(var.tags, { Experiment = "recovery" })
}

# ---------------------------------------------------------------------------
# 2 and 3. The same fault, guarded by alarms of different patience.
#
# for_each rather than two near-identical blocks, so there is no chance of the
# two experiments differing in some way other than the alarm -- which would
# invalidate the comparison the whole week rests on.
# ---------------------------------------------------------------------------
resource "aws_fis_experiment_template" "guarded" {
  for_each = var.stop_condition_alarms

  description = "Stop ${var.fault_percent}% of tasks, halted by the ${each.key} alarm."
  role_arn    = aws_iam_role.fis.arn

  stop_condition {
    source = "aws:cloudwatch:alarm"
    value  = each.value
  }

  target {
    name           = "tasks"
    resource_type  = local.common_target.resource_type
    selection_mode = local.common_target.selection_mode

    resource_tag {
      key   = "FISTarget"
      value = var.name
    }

    parameters = {
      cluster = var.cluster_name
      service = var.service_name
    }
  }

  action {
    name      = "stop-tasks"
    action_id = "aws:ecs:stop-task"
    target {
      key   = "Tasks"
      value = "tasks"
    }
  }

  log_configuration {
    log_schema_version = 2
    cloudwatch_logs_configuration {
      log_group_arn = "${aws_cloudwatch_log_group.fis.arn}:*"
    }
  }

  tags = merge(var.tags, { Experiment = each.key })
}
