#!/bin/bash
set -euo pipefail

echo "=== Week 10 — Centralised Logging Platform: Package Lambda zip ==="
echo ""
echo "This workspace (week-10-dev) is VCS-connected in HCP Terraform — HCP runs"
echo "plan/apply remotely from the GitHub repo, not from local terraform CLI."
echo "This script only rebuilds the Lambda zip. After running it:"
echo "  1. git add -f lambda/log_generator/log_generator.zip && git commit && git push"
echo "  2. In the HCP UI: Start new plan on week-10-dev, then confirm Apply"
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEEK_DIR="$(dirname "$SCRIPT_DIR")"

cd "$WEEK_DIR/lambda/log_generator"
zip -q log_generator.zip handler.py
echo "  Packaged log_generator.zip"

echo ""
echo "=== Packaging complete — commit, push, then apply via the HCP UI ==="
