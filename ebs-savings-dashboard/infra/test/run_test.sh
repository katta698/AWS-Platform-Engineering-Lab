#!/usr/bin/env bash
# run_test.sh — End-to-end personal account test
# Runs everything: Terraform → generate data → upload → crawl → open dashboard
set -euo pipefail

TEST_DIR="$(cd "$(dirname "$0")" && pwd)"
FRONTEND_DIR="$(cd "$TEST_DIR/../.." && pwd)"

echo "════════════════════════════════════════════════"
echo " EBS Savings Dashboard — Personal Account Test"
echo "════════════════════════════════════════════════"
echo ""

# ── Step 1: Terraform ─────────────────────────────────────────────────────────
echo "▶ [1/5] Terraform init + apply..."
cd "$TEST_DIR"
terraform init -upgrade -input=false
terraform apply -auto-approve -input=false

BUCKET=$(terraform output -raw cur_bucket)
API_URL=$(terraform output -raw api_url)
CRAWLER=$(terraform output -raw crawler_name)

echo ""
echo "  CUR bucket : $BUCKET"
echo "  API URL    : $API_URL"
echo "  Crawler    : $CRAWLER"
echo ""

# ── Step 2: Python deps ───────────────────────────────────────────────────────
echo "▶ [2/5] Installing Python dependencies..."
pip install --quiet pyarrow pandas boto3

# ── Step 3: Generate + upload synthetic CUR data ──────────────────────────────
echo "▶ [3/5] Generating synthetic CUR data and uploading to S3..."
python "$TEST_DIR/generate_mock_cur.py" \
  --upload \
  --bucket "$BUCKET" \
  --prefix "cur/synthetic-report"

# ── Step 4: Run Glue crawler ──────────────────────────────────────────────────
echo ""
echo "▶ [4/5] Starting Glue crawler (waiting for READY state)..."
aws glue start-crawler --name "$CRAWLER"

# Poll until crawler finishes
for i in $(seq 1 30); do
  STATE=$(aws glue get-crawler --name "$CRAWLER" --query 'Crawler.State' --output text)
  echo "  Crawler state: $STATE"
  if [ "$STATE" = "READY" ]; then
    break
  fi
  sleep 10
done

echo ""
echo "▶ [5/5] Pointing frontend at real API..."
cat > "$FRONTEND_DIR/.env.local" <<EOF
VITE_USE_MOCK=false
VITE_API_URL=$API_URL
EOF

echo ""
echo "════════════════════════════════════════════════"
echo " All done! Starting dashboard..."
echo " API URL: $API_URL"
echo " Open:    http://localhost:3000"
echo "════════════════════════════════════════════════"
echo ""

cd "$FRONTEND_DIR"
npm run dev
