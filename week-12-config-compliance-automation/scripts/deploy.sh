#!/bin/bash
set -euo pipefail

echo "=== Week 12 — AWS Config Compliance Automation: Deploy ==="
echo ""
echo "Workspace week-12-dev is VCS-connected in HCP Terraform — HCP runs"
echo "plan/apply remotely from the GitHub repo, not from local terraform CLI."
echo "This script rebuilds the reporter Lambda zip. After running it:"
echo "  1. git add -f week-12-config-compliance-automation/lambda/**/*.zip"
echo "     git commit && git push"
echo "  2. In the HCP UI: Start new plan on week-12-dev, then confirm Apply"
echo "  3. Confirm the SNS email subscription (check the alert_email inbox)"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/build_lambdas.sh"

echo ""
echo "=== Packaging complete — commit, push, then apply via the HCP UI ==="
echo ""
echo "After apply, exercise the pipeline end-to-end:"
echo "  ./generate_misconfig.sh    # untagged + unversioned/unencrypted bucket -> auto-fixed + digest"
echo "  aws configservice get-compliance-details-by-config-rule --config-rule-name week12-required-tags"
