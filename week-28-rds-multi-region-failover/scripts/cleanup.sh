#!/usr/bin/env bash
# Destroy week 28, then verify against the API in BOTH regions.
#
# Teardown is irreversible, so the figure gate runs first and refuses while a
# declared capture is missing.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
PRIMARY_REGION="us-east-1"
REPLICA_REGION="us-west-2"
NAME="week28-failover"

echo "==> figures captured?"
python "$ROOT/../scripts/check_figures_before_destroy.py" week-28-rds-multi-region-failover || {
  echo
  echo "REFUSING TO DESTROY: figures above are uncaptured."
  echo "Capture them, retire them in docs/UNUSED.txt, or pass --force."
  [ "${1:-}" = "--force" ] || exit 1
  shift
}

cd "$ROOT/terraform/environments/dev"
terraform plan -destroy -input=false -out=wk28-destroy.tfplan
terraform apply -input=false wk28-destroy.tfplan
rm -f wk28-destroy.tfplan

echo
echo "==> verifying against the API"
rc=0

# Both instances, each in its own region. A single-region check would have
# reported success while the replica carried on billing.
for pair in "${NAME}-primary:${PRIMARY_REGION}" "${NAME}-replica:${REPLICA_REGION}"; do
  id="${pair%%:*}"; region="${pair##*:}"
  if aws rds describe-db-instances --db-instance-identifier "$id" \
       --region "$region" >/dev/null 2>&1; then
    echo "  STILL PRESENT  db instance $id ($region)"
    rc=1
  else
    echo "  gone           db instance $id ($region)"
  fi
done

# A promoted replica is no longer named like a replica in anyone's head, but
# it keeps its identifier -- so the loop above still finds it. Snapshots are
# the other thing that outlives a destroy and keeps charging.
for region in "$PRIMARY_REGION" "$REPLICA_REGION"; do
  snaps=$(aws rds describe-db-snapshots --region "$region" --snapshot-type manual \
           --query "length(DBSnapshots[?starts_with(DBInstanceIdentifier,'${NAME}')])" \
           --output text 2>/dev/null || echo 0)
  [ "$snaps" != "0" ] && { echo "  STILL PRESENT  $snaps snapshot(s) in $region"; rc=1; } \
                      || echo "  gone           snapshots ($region)"
done

# $70/month prorated: the one resource where leaving it behind is expensive.
plans=$(aws arc-region-switch list-plans --region "$PRIMARY_REGION" \
         --query "length(plans[?name=='${NAME}'])" --output text 2>/dev/null || echo 0)
[ "$plans" != "0" ] && { echo "  STILL PRESENT  region switch plan $NAME"; rc=1; } \
                    || echo "  gone           region switch plan"

left=$(aws lambda list-functions --region "$PRIMARY_REGION" \
        --query "length(Functions[?starts_with(FunctionName,'${NAME}')])" \
        --output text 2>/dev/null || echo 0)
[ "$left" != "0" ] && { echo "  STILL PRESENT  $left lambda(s)"; rc=1; } \
                   || echo "  gone           lambda functions"

echo
[ "$rc" -eq 0 ] && echo "Teardown verified in both regions." || { echo "TEARDOWN INCOMPLETE"; exit 1; }
