#!/usr/bin/env bash
set -euo pipefail

WEEK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$WEEK_DIR/terraform/environments/dev"

echo "=== Week 08 — S3 Intelligent Storage Platform ==="
echo "=== Deploy ==="
echo ""

if [ ! -f "$TF_DIR/terraform.tfvars" ]; then
  echo "ERROR: terraform.tfvars not found."
  echo "  cp $TF_DIR/terraform.tfvars.example $TF_DIR/terraform.tfvars"
  echo "  Then fill in sns_email before running."
  exit 1
fi

cd "$TF_DIR"

echo ">>> terraform init"
terraform init

echo ""
echo ">>> terraform plan"
terraform plan -out=tfplan

echo ""
echo ">>> terraform apply"
terraform apply tfplan

echo ""
echo "=== Deploy complete ==="
echo ""
echo "Next steps:"
echo "  1. Confirm the SNS subscription from the email AWS just sent you."
echo "  2. Upload test objects:  aws s3 cp <file> s3://\$(terraform output -raw bucket_name)/logs/"
echo "  3. Invoke reporter now:  aws lambda invoke --function-name \$(terraform output -raw storage_reporter_function_name) out.json && cat out.json"
echo "  4. Storage Lens dashboard visible in S3 console after ~48 hours."
