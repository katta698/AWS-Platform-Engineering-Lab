#!/usr/bin/env bash
# deploy.sh — full deploy: Terraform apply + React build + S3 sync + CloudFront invalidation
# Usage: ./deploy.sh [dev|prod]
set -euo pipefail

ENV=${1:-dev}
INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
FRONTEND_DIR="$(cd "$INFRA_DIR/.." && pwd)"

echo "==> [1/5] Terraform init"
cd "$INFRA_DIR"
terraform init -upgrade

echo "==> [2/5] Terraform apply (environment=$ENV)"
terraform apply -var="environment=$ENV" -auto-approve

# Read outputs
API_URL=$(terraform output -raw api_invoke_url)
BUCKET=$(terraform output -raw frontend_bucket_name)
CF_ID=$(terraform output -raw cloudfront_id 2>/dev/null || echo "")

echo "==> [3/5] Build React frontend (VITE_USE_MOCK=false)"
cd "$FRONTEND_DIR"
VITE_USE_MOCK=false VITE_API_URL="$API_URL" npm run build

echo "==> [4/5] Sync dist/ to s3://$BUCKET"
# Long-cache for hashed assets, no-cache for index.html
aws s3 sync dist/ "s3://$BUCKET" \
  --cache-control "public,max-age=31536000,immutable" \
  --exclude "index.html"

aws s3 cp dist/index.html "s3://$BUCKET/index.html" \
  --cache-control "no-cache,no-store,must-revalidate"

echo "==> [5/5] CloudFront invalidation"
if [ -n "$CF_ID" ]; then
  aws cloudfront create-invalidation \
    --distribution-id "$CF_ID" \
    --paths "/*" \
    --query 'Invalidation.Id' \
    --output text
fi

echo ""
echo "✓ Deploy complete"
echo "  Dashboard: https://$(cd "$INFRA_DIR" && terraform output -raw cloudfront_url 2>/dev/null || echo '<see terraform output>')"
echo "  API URL:   $API_URL"
