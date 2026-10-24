#!/usr/bin/env bash
# run-experiment.sh -- start a FIS experiment and time what actually happened.
#
#   bash scripts/run-experiment.sh recovery
#   bash scripts/run-experiment.sh fast
#   bash scripts/run-experiment.sh typical
#
# WHY A SCRIPT RATHER THAN THE CONSOLE
# ------------------------------------
# The whole week is one number: how long the damage ran before the safety net
# caught it. Reading that off a console by eye gives you "about a minute" and
# "a while", which is not a finding. This records timestamps to the second,
# from the API, into a file -- so the post quotes measurements rather than
# impressions.
#
# What it records, per second, until the experiment ends:
#   - FIS experiment state           (initiating -> running -> completed/stopped)
#   - healthy and unhealthy targets  (what the load balancer can see)
#   - both alarm states              (which net was armed, and when it tripped)
set -euo pipefail

LABEL="${1:?usage: run-experiment.sh <recovery|fast|typical>}"
TF="$(cd "$(dirname "$0")/../terraform/environments/dev" && pwd)"
OUT="$(cd "$(dirname "$0")/.." && pwd)/results"
REGION="${REGION:-us-east-1}"
MAX_SECONDS="${MAX_SECONDS:-900}"

mkdir -p "$OUT"

tfout() { terraform -chdir="$TF" output -json "$1"; }

TEMPLATE_ID="$(tfout experiments | python -c "import json,sys;print(json.load(sys.stdin)['$LABEL'])")"
TG="$(terraform -chdir="$TF" output -raw target_group_arn_suffix 2>/dev/null || true)"
if [ -z "$TG" ]; then
  # Not exported at the top level; read it out of the service module instead.
  TG="$(aws elbv2 describe-target-groups --names "$(terraform -chdir="$TF" output -raw cluster_name)" \
        --region "$REGION" --query 'TargetGroups[0].TargetGroupArn' --output text)"
fi
ALARM_FAST="$(tfout alarms | python -c "import json,sys;print(json.load(sys.stdin)['fast'])")"
ALARM_TYPICAL="$(tfout alarms | python -c "import json,sys;print(json.load(sys.stdin)['typical'])")"
TG_ARN="$(aws elbv2 describe-target-groups --region "$REGION" \
          --query "TargetGroups[?contains(TargetGroupArn, '${TG##*/}')].TargetGroupArn | [0]" \
          --output text 2>/dev/null || echo "$TG")"

CSV="$OUT/${LABEL}-$(date -u +%Y%m%dT%H%M%SZ).csv"
echo "experiment : $LABEL ($TEMPLATE_ID)"
echo "recording  : $CSV"
echo

ID="$(aws fis start-experiment --experiment-template-id "$TEMPLATE_ID" \
      --region "$REGION" --query 'experiment.id' --output text)"
START_EPOCH="$(date -u +%s)"
echo "started    : $ID"
echo

echo "elapsed_s,fis_state,healthy,unhealthy,alarm_fast,alarm_typical" > "$CSV"

alarm_state() {
  aws cloudwatch describe-alarms --alarm-names "$1" --region "$REGION" \
    --query 'MetricAlarms[0].StateValue' --output text 2>/dev/null || echo "?"
}

printf '%8s  %-12s  %7s  %9s  %-6s  %-6s\n' ELAPSED FIS HEALTHY UNHEALTHY FAST TYPICAL
while :; do
  NOW="$(date -u +%s)"
  ELAPSED=$(( NOW - START_EPOCH ))

  STATE="$(aws fis get-experiment --id "$ID" --region "$REGION" \
           --query 'experiment.state.status' --output text)"

  COUNTS="$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --region "$REGION" \
            --query 'TargetHealthDescriptions[].TargetHealth.State' --output text 2>/dev/null || echo "")"
  HEALTHY=$(echo "$COUNTS" | tr '\t' '\n' | grep -c '^healthy$' || true)
  UNHEALTHY=$(echo "$COUNTS" | tr '\t' '\n' | grep -vc '^healthy$' || true)

  AF="$(alarm_state "$ALARM_FAST")"
  AT="$(alarm_state "$ALARM_TYPICAL")"

  printf '%8s  %-12s  %7s  %9s  %-6s  %-6s\n' "$ELAPSED" "$STATE" "$HEALTHY" "$UNHEALTHY" "$AF" "$AT"
  echo "$ELAPSED,$STATE,$HEALTHY,$UNHEALTHY,$AF,$AT" >> "$CSV"

  case "$STATE" in
    completed|stopped|failed) break ;;
  esac
  [ "$ELAPSED" -ge "$MAX_SECONDS" ] && { echo "gave up after ${MAX_SECONDS}s"; break; }
  sleep 5
done

echo
echo "final state : $STATE"
aws fis get-experiment --id "$ID" --region "$REGION" \
  --query 'experiment.{stopped:state.reason,start:startTime,end:endTime}' --output table
echo
echo "recorded    : $CSV"
echo "summarise   : python scripts/summarise.py $CSV"
