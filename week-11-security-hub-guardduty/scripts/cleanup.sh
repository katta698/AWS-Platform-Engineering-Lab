#!/bin/bash
set -euo pipefail

echo "=== Week 11 — Cleanup ==="
echo ""
echo "Infrastructure is managed by HCP Terraform (workspace week-11-dev)."
echo "To tear it down: HCP UI -> week-11-dev -> Settings -> Destruction -> "
echo "'Queue destroy plan', then confirm. That disables Security Hub CSPM and"
echo "the GuardDuty detector and removes the Lambdas/rules/SNS/DLQ."
echo ""
echo "Note: destroying is inexpensive to reverse — one HCP apply rebuilds it."
echo ""
echo "This script only removes leftover TEST resources the misconfig generator"
echo "created (in case a remediator did not fully clean them, or you want a"
echo "fresh re-test). Pass the SG id and bucket name printed by generate_misconfig.sh:"
echo "  ./cleanup.sh <sg-id> <bucket-name>"
echo ""

export AWS_PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-east-1}"
SG_ID="${1:-}"
BUCKET="${2:-}"

if [[ -n "$SG_ID" ]]; then
  echo "Deleting security group $SG_ID ..."
  aws ec2 delete-security-group --region "$REGION" --group-id "$SG_ID" \
    && echo "  deleted" || echo "  (already gone or in use)"
fi

if [[ -n "$BUCKET" ]]; then
  echo "Emptying and deleting bucket $BUCKET ..."
  aws s3 rm "s3://$BUCKET" --recursive --region "$REGION" >/dev/null 2>&1 || true
  aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION" \
    && echo "  deleted" || echo "  (already gone)"
fi

echo ""
echo "GuardDuty sample findings self-expire; no cleanup needed for those."
