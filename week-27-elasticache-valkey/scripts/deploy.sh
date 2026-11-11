#!/usr/bin/env bash
# Deploy week 27: build the package, then apply.
#
# A serverless cache takes a few minutes to become available. It bills
# ~$0.0084/hour on the 100 MB floor, plus ECPUs for what the run moves.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"

"$HERE/build_package.sh"
cd "$ROOT/terraform/environments/dev"
terraform init -input=false
terraform apply -input=false "$@"

echo
echo "Next: python scripts/run_experiment.py"
