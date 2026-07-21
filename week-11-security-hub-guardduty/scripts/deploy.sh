#!/bin/bash
set -euo pipefail

echo "=== Week 11 — Security Hub + GuardDuty Auto-Remediation: Deploy ==="
echo ""
echo "Workspace week-11-dev is VCS-connected in HCP Terraform — HCP runs"
echo "plan/apply remotely from the GitHub repo, not from local terraform CLI."
echo "This script rebuilds the Lambda zips. After running it:"
echo "  1. git add -f week-11-security-hub-guardduty/lambda/**/*.zip"
echo "     git commit && git push"
echo "  2. In the HCP UI: Start new plan on week-11-dev, then confirm Apply"
echo "  3. Confirm the SNS email subscription (check the alert_email inbox)"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/build_lambdas.sh"

echo ""
echo "=== Packaging complete — commit, push, then apply via the HCP UI ==="
echo ""
echo "After apply, exercise the pipeline end-to-end:"
echo "  ./generate_misconfig.sh          # open SG + public bucket -> auto-fixed"
echo "  ./trigger_guardduty_sample.sh    # GuardDuty threat -> SNS notify"
