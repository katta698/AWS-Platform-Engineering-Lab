# Org-wide centralization rule: physically copies matching log groups from
# every account/region in scope into the destination account. First copy has
# no ingestion charge; only log data written AFTER rule creation is copied.
#
# Runs from the org management account. Prerequisite (no Terraform resource
# exists for it — provider issue #44698 still open): Organizations trusted
# access for CloudWatch must already be enabled. See README "Prerequisites".
resource "aws_observabilityadmin_centralization_rule_for_organization" "this" {
  rule_name = var.rule_name

  rule {
    source {
      regions = [var.source_region]
      scope   = "OrganizationId = '${var.organization_id}'"

      source_logs_configuration {
        # Lab has no KMS-encrypted log groups; skip rather than re-encrypt.
        encrypted_log_group_strategy = "SKIP"
        # VERIFY at first plan/apply: LIKE wildcard grammar ('%' assumed, per
        # the feature's documented operator set) — adjust if apply rejects it.
        log_group_selection_criteria = "LogGroupName LIKE '${var.log_group_prefix}%'"
      }
    }

    destination {
      account = var.destination_account_id
      region  = var.destination_region
    }
  }
}
