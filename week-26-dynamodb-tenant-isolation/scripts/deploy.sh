#!/usr/bin/env bash
# Deploy week 26: build the package, then apply.
#
# Expect the apply to take roughly 10-12 minutes, nearly all of it the DAX
# cluster. Three nodes are provisioned one at a time and the resource does not
# return until the cluster is available.
#
# From the moment the cluster exists it bills at ~$0.12/hour whether anything
# reads from it or not. ./scripts/cleanup.sh when finished.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"

"$HERE/build_package.sh"

cd "$ROOT/terraform/environments/dev"

echo
echo "==> terraform init"
terraform init -input=false

echo
echo "==> terraform apply"
terraform apply -input=false "$@"

echo
echo "==> seeding both tenants"
python "$HERE/seed.py"

echo
echo "Deployed. Run ./scripts/prove_isolation.py next."
echo "DAX is now billing. ./scripts/cleanup.sh when you are done."
