#!/bin/bash
set -euo pipefail

echo "=== Week 06 — Account Vending Machine Cleanup ==="
echo ""
echo "terraform destroy removes the OUs, SCP, Lambda, Step Functions, and API"
echo "Gateway. It does NOT touch any AWS account that was actually vended through"
echo "this pipeline — those accounts are NOT in Terraform state."
echo ""
echo "AWS will refuse to delete a non-empty OU. If you vended any test accounts,"
echo "first move them back to the Organization root (or close them) via the"
echo "Organizations console BEFORE running this, or terraform destroy will fail"
echo "on the organizations module."
echo ""
echo "Closing a vended account is also not instant — closed accounts enter a"
echo "~90 day suspension window, they are not deleted immediately."
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TF_DIR="$(dirname "$SCRIPT_DIR")/terraform/environments/dev"

read -rp "Type DESTROY to confirm: " confirm
if [[ "$confirm" != "DESTROY" ]]; then
  echo "Aborted."
  exit 1
fi

cd "$TF_DIR"
terraform destroy -auto-approve

echo "=== Cleanup complete — $0 done ==="
