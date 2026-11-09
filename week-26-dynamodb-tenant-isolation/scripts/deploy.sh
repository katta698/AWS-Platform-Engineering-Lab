#!/usr/bin/env bash
# Deploy week 26: build the package, apply, seed.
#
# ~10-12 minutes, nearly all of it the DAX cluster. It bills ~$0.12/hour from
# the moment it exists. ./scripts/cleanup.sh when finished.
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
