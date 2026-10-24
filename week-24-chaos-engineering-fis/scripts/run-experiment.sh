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
MAX_SECONDS="${MAX_SECONDS:-1500}"
SETTLE_SECONDS="${SETTLE_SECONDS:-300}"   # how long to keep watching after FIS ends
DESIRED="${DESIRED:-4}"                   # healthy targets that mean "whole"

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

alarm_state() {
  aws cloudwatch describe-alarms --alarm-names "$1" --region "$REGION"     --query 'MetricAlarms[0].StateValue' --output text 2>/dev/null || echo "?"
}

# PRE-FLIGHT: refuse to start against an alarm that is already tripped.
#
# A stop condition already in ALARM stops the experiment at t=0. FIS reports
# "stopped", the CSV has one row, and the run looks like an instant, heroic
# save. It is nothing of the kind -- it measured a stale alarm.
#
# This matters because the alarms do not reset quickly. The typical alarm
# needs two clean 300s datapoints, so it stays in ALARM for ten minutes after
# the service has fully recovered. Back-to-back runs are exactly the case
# where this bites.
GUARD=""
case "$LABEL" in
  fast)    GUARD="$ALARM_FAST" ;;
  typical) GUARD="$ALARM_TYPICAL" ;;
esac
if [ -n "$GUARD" ]; then
  GS="$(alarm_state "$GUARD")"
  if [ "$GS" != "OK" ]; then
    echo "REFUSING TO START."
    echo "  guarding alarm : $GUARD"
    echo "  current state  : $GS  (needs to be OK)"
    echo
    echo "  Starting now would stop the experiment immediately and record a"
    echo "  measurement of the previous run, not this one. Wait for the alarm"
    echo "  to clear -- the typical alarm takes ~10 minutes -- and retry."
    exit 2
  fi
  echo "pre-flight : $LABEL guard is OK"
fi

# Baseline health, so "impact" is measured against a service that was
# actually whole when the experiment began.
BASE="$(aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --region "$REGION"         --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' --output text)"
echo "pre-flight : $BASE healthy targets before injection"
if [ "$BASE" -lt "$DESIRED" ]; then
  echo "REFUSING TO START: expected $DESIRED healthy targets, found $BASE."
  echo "  The service has not finished recovering from an earlier run."
  exit 2
fi
echo

ID="$(aws fis start-experiment --experiment-template-id "$TEMPLATE_ID"       --region "$REGION" --query 'experiment.id' --output text)"
START_EPOCH="$(date -u +%s)"
echo "started    : $ID"
echo

echo "elapsed_s,phase,fis_state,healthy,unhealthy,alarm_fast,alarm_typical" > "$CSV"

# WHY THE LOOP DOES NOT END WHEN FIS DOES
# ---------------------------------------
# FIS reports "completed" when its last action RETURNS, not when the fault has
# finished playing out. Measured on the baseline run: FIS said completed at
# 22:56:31; ECS started replacement tasks at 22:57:08 and the original tasks
# did not reach STOPPED until 22:57:41 -- seventy seconds after the experiment
# was officially over.
#
# A loop that exits on the terminal state therefore stops watching slightly
# BEFORE the damage it exists to measure. The first version of this script did
# exactly that and recorded a flat line of four healthy targets through a run
# that demonstrably halved the service.
#
# So: keep sampling until the service is observed whole again for three
# consecutive polls, or until the settle cap expires.
RECOVERED_STREAK=0
TERMINAL_AT=""
PHASE="experiment"

printf '%8s  %-10s  %-12s  %7s  %9s  %-6s  %-6s
' ELAPSED PHASE FIS HEALTHY UNHEALTHY FAST TYPICAL
while :; do
  NOW="$(date -u +%s)"
  ELAPSED=$(( NOW - START_EPOCH ))

  # Fired in parallel. Run serially these four calls take ~11s, which made the
  # old sampling interval 16s -- far too coarse to time a 60s alarm against a
  # 300s one.
  T="$(mktemp -d)"
  aws fis get-experiment --id "$ID" --region "$REGION"       --query 'experiment.state.status' --output text > "$T/state" 2>/dev/null &
  aws elbv2 describe-target-health --target-group-arn "$TG_ARN" --region "$REGION"       --query 'TargetHealthDescriptions[].TargetHealth.State' --output text > "$T/health" 2>/dev/null &
  alarm_state "$ALARM_FAST"    > "$T/af" &
  alarm_state "$ALARM_TYPICAL" > "$T/at" &
  wait

  STATE="$(cat "$T/state" 2>/dev/null || echo '?')"
  COUNTS="$(cat "$T/health" 2>/dev/null || echo '')"
  AF="$(cat "$T/af" 2>/dev/null || echo '?')"
  AT="$(cat "$T/at" 2>/dev/null || echo '?')"
  rm -rf "$T"

  HEALTHY=$(echo "$COUNTS" | tr '	' '
' | grep -c '^healthy$' || true)
  UNHEALTHY=$(echo "$COUNTS" | tr '	' '
' | grep -c '^\(unhealthy\|draining\|unused\|initial\)$' || true)

  printf '%8s  %-10s  %-12s  %7s  %9s  %-6s  %-6s
'     "$ELAPSED" "$PHASE" "$STATE" "$HEALTHY" "$UNHEALTHY" "$AF" "$AT"
  echo "$ELAPSED,$PHASE,$STATE,$HEALTHY,$UNHEALTHY,$AF,$AT" >> "$CSV"

  case "$STATE" in
    completed|stopped|failed)
      if [ -z "$TERMINAL_AT" ]; then
        TERMINAL_AT="$ELAPSED"
        PHASE="aftermath"
        echo "  -- FIS reported $STATE at ${ELAPSED}s; still watching the service --"
      fi
      ;;
  esac

  if [ -n "$TERMINAL_AT" ]; then
    if [ "$HEALTHY" -ge "$DESIRED" ] && [ "$UNHEALTHY" -eq 0 ]; then
      RECOVERED_STREAK=$(( RECOVERED_STREAK + 1 ))
    else
      RECOVERED_STREAK=0
    fi
    [ "$RECOVERED_STREAK" -ge 3 ] && { echo "  -- service whole for 3 consecutive polls --"; break; }
    [ $(( ELAPSED - TERMINAL_AT )) -ge "$SETTLE_SECONDS" ] && {
      echo "  -- settle cap ${SETTLE_SECONDS}s reached --"; break; }
  fi

  [ "$ELAPSED" -ge "$MAX_SECONDS" ] && { echo "gave up after ${MAX_SECONDS}s"; break; }
  sleep 2
done

echo
echo "final state : $STATE"
aws fis get-experiment --id "$ID" --region "$REGION"   --query 'experiment.{stopped:state.reason,start:startTime,end:endTime}' --output table
echo
echo "recorded    : $CSV"
echo "summarise   : python scripts/summarise.py $CSV"
