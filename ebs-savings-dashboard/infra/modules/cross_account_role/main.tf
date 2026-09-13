data "aws_iam_policy_document" "assume" {
  statement {
    sid     = "AllowLambdaFromMgmtAccount"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [var.lambda_role_arn]
    }
    # Only allow assumption from within the org — defence in depth
    dynamic "condition" {
      for_each = var.org_id != "" ? [1] : []
      content {
        test     = "StringEquals"
        variable = "aws:PrincipalOrgID"
        values   = [var.org_id]
      }
    }
  }
}

resource "aws_iam_role" "ebs_read" {
  name                 = "EBSDashboardReadRole"
  description          = "Read-only EBS data for the EBS Savings Dashboard Lambda"
  assume_role_policy   = data.aws_iam_policy_document.assume.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "ebs_read" {
  statement {
    sid    = "EC2ReadOnly"
    effect = "Allow"
    actions = [
      "ec2:DescribeVolumes",
      "ec2:DescribeInstances",
      "ec2:DescribeSnapshots",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeRegions",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ebs_read" {
  name   = "ebs-read-only"
  role   = aws_iam_role.ebs_read.id
  policy = data.aws_iam_policy_document.ebs_read.json
}
