#!/usr/bin/env bash
# Destroy week 27, then verify against the API.
#
# Teardown is irreversible, so the figure gate runs first and refuses while a
# declared capture is missing.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
REGION="${AWS_REGION:-us-east-1}"
NAME="week27-valkey"

echo "==> figures captured?"
python "$ROOT/../scripts/check_figures_before_destroy.py" week-27-elasticache-valkey || {
  echo
  echo "REFUSING TO DESTROY: figures above are uncaptured."
  echo "Capture them, retire them in docs/UNUSED.txt, or pass --force."
  [ "${1:-}" = "--force" ] || exit 1
  shift
}

cd "$ROOT/terraform/environments/dev"
terraform plan -destroy -input=false -out=wk27-destroy.tfplan
terraform apply -input=false wk27-destroy.tfplan
rm -f wk27-destroy.tfplan

echo
echo "==> verifying against the API"
rc=0
if aws elasticache describe-serverless-caches --serverless-cache-name "$NAME" \
     --region "$REGION" >/dev/null 2>&1; then
  echo "  STILL PRESENT  serverless cache $NAME"
  rc=1
else
  echo "  gone           serverless cache $NAME"
fi

left=$(aws lambda list-functions --region "$REGION" \
        --query "length(Functions[?starts_with(FunctionName,'${NAME}')])" \
        --output text 2>/dev/null || echo 0)
[ "$left" != "0" ] && { echo "  STILL PRESENT  $left lambda(s)"; rc=1; } \
                   || echo "  gone           lambda functions"

echo
[ "$rc" -eq 0 ] && echo "Teardown verified." || { echo "TEARDOWN INCOMPLETE"; exit 1; }
