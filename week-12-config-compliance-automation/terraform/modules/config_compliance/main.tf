###############################################################################
# Config compliance module -- one conformance pack containing 3 Config rules
# and 2 remediation configurations.
#
# A conformance pack is self-contained: its template *defines* its own
# AWS::Config::ConfigRule / AWS::Config::RemediationConfiguration resources
# rather than wrapping externally-created ones. So this module creates no
# standalone aws_config_config_rule resources -- only the pack, plus the IAM
# role its remediations assume. This also means the pack's own console
# compliance view is the real, non-duplicated source of truth ("Compliance
# Dashboard"), not a second copy of rules that already exist as securityhub-*
# (Week 11) or elsewhere.
###############################################################################

data "aws_partition" "current" {}

# --- Role SSM Automation assumes to perform the two S3 remediations -----------
data "aws_iam_policy_document" "ssm_automation_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ssm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ssm_automation" {
  name               = "${var.name_prefix}-ssm-automation-role"
  assume_role_policy = data.aws_iam_policy_document.ssm_automation_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy" "ssm_automation" {
  name = "${var.name_prefix}-ssm-automation-policy"
  role = aws_iam_role.ssm_automation.id

  # Scoped to only the opted-in resources -- same defense-in-depth pattern as
  # Week 11's remediator IAM (Config's own tag Scope already limits which
  # buckets get evaluated/remediated; this condition means IAM refuses the
  # call on anything untagged too).
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "S3ComplianceRemediation"
        Effect   = "Allow"
        Action   = ["s3:PutBucketVersioning", "s3:PutBucketEncryption"]
        Resource = "arn:${data.aws_partition.current.partition}:s3:::*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/${var.remediation_tag_key}" = var.remediation_tag_value
          }
        }
      },
    ]
  })
}

# --- Conformance pack: rules + remediations, one deployable unit --------------
resource "aws_config_conformance_pack" "this" {
  name = "${var.name_prefix}-pack"

  template_body = templatefile("${path.module}/templates/conformance-pack.yaml.tpl", {
    automation_role_arn   = aws_iam_role.ssm_automation.arn
    remediation_tag_key   = var.remediation_tag_key
    remediation_tag_value = var.remediation_tag_value
    required_tag_1        = var.required_tag_keys[0]
    required_tag_2        = var.required_tag_keys[1]
    required_tag_3        = var.required_tag_keys[2]
  })

  # The remediation's AutomationAssumeRole must exist before Config tries to
  # use it on the first evaluation.
  depends_on = [aws_iam_role_policy.ssm_automation]
}
