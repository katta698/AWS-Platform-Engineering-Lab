###############################################################################
# Security Hub CSPM — the aggregation hub and posture-finding source.
#
# We use classic Security Hub CSPM (aws_securityhub_account), not the unified
# "AWS Security Hub" v2 that GA'd Dec 2025: the Terraform provider does not yet
# stably support v2 (aws_securityhub_account_v2 is still a feature request as of
# mid-2026). v2 is a correlation/analytics layer; the auto-remediation substrate
# — findings -> automation rules -> EventBridge -> Lambda — is 100% classic CSPM.
###############################################################################

data "aws_region" "current" {}
data "aws_partition" "current" {}

resource "aws_securityhub_account" "this" {
  # We subscribe to standards explicitly below, so don't also auto-enable the
  # default set (avoids a second standard's findings muddying the demo).
  enable_default_standards = false
  # New controls added to a subscribed standard are enabled automatically.
  auto_enable_controls = true
  # Consolidated control findings (one finding per control, not per standard).
  control_finding_generator = "SECURITY_CONTROL"
}

# AWS Foundational Security Best Practices — the source of the config findings
# our Lambdas remediate (EC2.13/14/19 open ports, S3.2/3/8 public buckets).
resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:${data.aws_partition.current.partition}:securityhub:${data.aws_region.current.region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

# One place to see findings across regions — matches a real multi-region posture
# even though this lab runs a single region.
resource "aws_securityhub_finding_aggregator" "this" {
  linking_mode = "ALL_REGIONS"
  depends_on   = [aws_securityhub_account.this]
}

# Automation rule — runs INSIDE Security Hub, BEFORE any EventBridge rule fires.
# Enriches findings so downstream routing/paging is smarter: any failed control
# on a resource tagged as production is escalated to CRITICAL severity.
resource "aws_securityhub_automation_rule" "escalate_prod" {
  description = "Escalate failed findings on production-tagged resources to CRITICAL"
  rule_name   = "${var.name_prefix}-escalate-prod-failed"
  rule_order  = 1
  rule_status = "ENABLED"

  criteria {
    resource_tags {
      comparison = "EQUALS"
      key        = var.production_tag_key
      value      = var.production_tag_value
    }
    compliance_status {
      comparison = "EQUALS"
      value      = "FAILED"
    }
  }

  actions {
    type = "FINDING_FIELDS_UPDATE"
    finding_fields_update {
      severity {
        label = "CRITICAL"
      }
      note {
        text       = "Auto-escalated: failed control on a production-tagged resource."
        updated_by = "securityhub-automation-rule"
      }
    }
  }

  depends_on = [aws_securityhub_account.this]
}
