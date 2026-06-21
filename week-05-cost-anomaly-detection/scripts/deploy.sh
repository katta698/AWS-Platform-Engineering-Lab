#!/usr/bin/env bash
# deploy.sh — applies week-05 infrastructure via HCP Terraform
# For VCS-driven runs this is optional (HCP applies on merge to main).
# Use this for local CLI-driven plan/apply during development.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_ROOT/terraform/environments/dev"

echo "==> Week 05 — Cost Anomaly Detection"
echo "    Terraform dir : $TF_DIR"
echo "    HCP org       : Katta"
echo "    HCP workspace : week-05-dev"
echo ""

cd "$TF_DIR"

echo "==> terraform init  (authenticates to HCP, downloads providers)"
terraform init

echo "==> terraform plan"
terraform plan -out=tfplan

echo "==> terraform apply"
terraform apply tfplan

echo ""
echo "==> Done. Next steps:"
echo "    1. Check your inbox — confirm the SNS email subscription from AWS."
echo "    2. Verify monitor in AWS Console: Cost Management > Anomaly Detection"
echo "    3. To test: use scripts/test_alert.sh to send a mock SNS payload."
