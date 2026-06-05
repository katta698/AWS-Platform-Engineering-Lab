#!/bin/bash
set -euo pipefail

echo "=== Week 04 — Fleet Intelligence Platform Cleanup ==="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(dirname "$SCRIPT_DIR")/terraform/environments/dev"

echo "This will destroy ALL Week 04 resources (S3 buckets, Glue, Athena, Lambda, Step Functions)."
read -rp "Type DESTROY to confirm: " confirm
if [[ "$confirm" != "DESTROY" ]]; then
  echo "Aborted."
  exit 1
fi

cd "$TF_DIR"
terraform destroy -auto-approve

echo "=== Cleanup complete — $0 done ==="
