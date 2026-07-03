#!/usr/bin/env bash
set -euo pipefail

WEEK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$WEEK_DIR/terraform/environments/dev"

echo "=== Week 08 — S3 Intelligent Storage Platform ==="
echo "=== Cleanup ==="
echo ""

cd "$TF_DIR"

BUCKET_NAME=$(terraform output -raw bucket_name 2>/dev/null || echo "")

if [ -n "$BUCKET_NAME" ]; then
  echo ">>> Emptying bucket: $BUCKET_NAME"
  echo "    (S3 buckets must be empty before Terraform can destroy them)"

  # Delete all object versions (required when versioning is enabled)
  aws s3api list-object-versions \
    --bucket "$BUCKET_NAME" \
    --query 'Versions[].{Key:Key,VersionId:VersionId}' \
    --output json 2>/dev/null | \
    jq -r '.[] | "\(.Key) \(.VersionId)"' | \
    while read -r key version_id; do
      aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id" > /dev/null
    done || true

  # Delete all delete markers
  aws s3api list-object-versions \
    --bucket "$BUCKET_NAME" \
    --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
    --output json 2>/dev/null | \
    jq -r '.[] | "\(.Key) \(.VersionId)"' | \
    while read -r key version_id; do
      aws s3api delete-object --bucket "$BUCKET_NAME" --key "$key" --version-id "$version_id" > /dev/null
    done || true

  echo "    Bucket emptied."
fi

echo ""
echo ">>> terraform destroy"
terraform destroy -auto-approve

echo ""
echo "=== Cleanup complete. All resources destroyed. ==="
