#!/bin/bash
set -euo pipefail

echo "=== Week 04 — Fleet Intelligence Platform Deploy ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WEEK_DIR="$(dirname "$SCRIPT_DIR")"
TF_DIR="$WEEK_DIR/terraform/environments/dev"
RAW_BUCKET="jay-fleet-intelligence-raw-dev"

# ── 1. Package Lambda functions ───────────────────────────────────────────────
echo "[1/5] Packaging Lambda functions..."
for fn in webhook_receiver glue_trigger status_updater; do
  cd "$WEEK_DIR/lambda/$fn"
  zip -q "${fn}.zip" handler.py
  echo "  Packaged $fn.zip"
done

# ── 2. Upload Glue ETL script to S3 ──────────────────────────────────────────
echo "[2/5] Uploading Glue ETL script to S3..."
aws s3 cp "$WEEK_DIR/glue/scripts/fleet_etl.py" \
  "s3://$RAW_BUCKET/scripts/fleet_etl.py" \
  --region us-east-1 2>/dev/null || echo "  (bucket not yet created — will upload after terraform apply)"

# ── 3. Terraform init ─────────────────────────────────────────────────────────
echo "[3/5] Terraform init..."
cd "$TF_DIR"
terraform init -upgrade

# ── 4. Terraform apply ────────────────────────────────────────────────────────
echo "[4/5] Terraform apply..."
terraform apply -auto-approve

# ── 5. Upload ETL script (now bucket exists) ──────────────────────────────────
echo "[5/5] Uploading Glue ETL script..."
aws s3 cp "$WEEK_DIR/glue/scripts/fleet_etl.py" \
  "s3://$RAW_BUCKET/scripts/fleet_etl.py" \
  --region us-east-1

echo ""
echo "=== Deploy complete ==="
terraform output
