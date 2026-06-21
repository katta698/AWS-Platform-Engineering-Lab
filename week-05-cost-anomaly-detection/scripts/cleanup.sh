#!/usr/bin/env bash
# cleanup.sh — destroys all week-05 resources
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_ROOT/terraform/environments/dev"

echo "==> Destroying week-05-cost-anomaly-detection (dev)"
echo "    This will remove: Cost Anomaly Monitor, Subscriptions, SNS Topics, Lambda, IAM roles"
echo ""
read -p "Are you sure? (yes/no): " CONFIRM
[[ "$CONFIRM" != "yes" ]] && echo "Aborted." && exit 1

cd "$TF_DIR"
terraform destroy -auto-approve
echo "==> Cleanup complete."
