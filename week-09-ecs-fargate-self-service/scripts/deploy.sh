#!/bin/bash
set -euo pipefail

echo "=== Week 09 — ECS Fargate Self-Service: Package Lambda zips ==="
echo ""
echo "This workspace (week-09-dev) is VCS-connected in HCP Terraform — HCP runs"
echo "plan/apply remotely from the GitHub repo, not from local terraform CLI."
echo "This script only rebuilds the 3 Lambda zips. After running it:"
echo "  1. git add lambda/*/*.zip && git commit && git push"
echo "  2. In the HCP UI: Start new plan on week-09-dev, then confirm Apply"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEEK_DIR="$(dirname "$SCRIPT_DIR")"

for fn in webhook_receiver fargate_provisioner status_notifier; do
  cd "$WEEK_DIR/lambda/$fn"
  zip -q "${fn}.zip" handler.py
  echo "  Packaged $fn.zip"
done

echo ""
echo "=== Packaging complete — commit, push, then apply via the HCP UI ==="
