#!/bin/bash
set -euo pipefail

echo "=== Week 12 — Cleanup ==="
echo ""
echo "Infrastructure is managed by HCP Terraform (workspace week-12-dev)."
echo "To tear it down: HCP UI -> week-12-dev -> Settings -> Destruction -> "
echo "'Queue destroy plan', then confirm. That removes the conformance pack"
echo "(and its 3 rules + 2 remediations), the reporter Lambda/schedule/SNS/DLQ,"
echo "and the SSM automation IAM role. The account's pre-existing Config"
echo "recorder (telemetry-dashboard-recorder) is untouched — this week never"
echo "created it and must not delete it."
echo ""
echo "Note: destroying is inexpensive to reverse — one HCP apply rebuilds it."
echo ""
echo "This script only removes leftover TEST buckets the misconfig generator"
echo "created (in case remediation did not fully clean them, or you want a"
echo "fresh re-test). Pass the two bucket names printed by generate_misconfig.sh:"
echo "  ./cleanup.sh <remediate-bucket> <untagged-bucket>"
echo ""

export AWS_PROFILE="${AWS_PROFILE:-default}"
REGION="${AWS_REGION:-us-east-1}"
REMEDIATE_BUCKET="${1:-}"
UNTAGGED_BUCKET="${2:-}"

for BUCKET in "$REMEDIATE_BUCKET" "$UNTAGGED_BUCKET"; do
  if [[ -n "$BUCKET" ]]; then
    echo "Emptying and deleting bucket $BUCKET ..."
    aws s3 rm "s3://$BUCKET" --recursive --region "$REGION" >/dev/null 2>&1 || true
    aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION" \
      && echo "  deleted" || echo "  (already gone)"
  fi
done
