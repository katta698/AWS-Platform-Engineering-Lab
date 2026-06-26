#!/bin/bash
set -euo pipefail

echo "=== Week 06 — Account Vending Machine Deploy ==="
echo "NOTE: must run with credentials for the Organizations MANAGEMENT account."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEEK_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$WEEK_DIR/terraform/environments/dev"

# ── 1. Package Lambda functions ───────────────────────────────────────────────
echo "[1/3] Packaging Lambda functions..."
for fn in webhook_receiver account_creator account_mover status_notifier; do
  cd "$WEEK_DIR/lambda/$fn"
  zip -q "${fn}.zip" handler.py
  echo "  Packaged $fn.zip"
done

# ── 2. Terraform init ─────────────────────────────────────────────────────────
echo "[2/3] Terraform init..."
cd "$TF_DIR"
terraform init -upgrade

# ── 3. Terraform apply ────────────────────────────────────────────────────────
echo "[3/3] Terraform apply..."
terraform apply -auto-approve

echo ""
echo "=== Deploy complete ==="
echo "This created the OUs, SCP guardrails, and the vending pipeline (Lambda/Step"
echo "Functions/API Gateway) — it did NOT vend any accounts yet."
echo "Submitting an account-vending ticket through the webhook creates a REAL AWS"
echo "account that cannot be deleted instantly (closed accounts suspend ~90 days)."
echo ""
terraform output
