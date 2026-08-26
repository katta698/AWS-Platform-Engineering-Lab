#!/usr/bin/env bash
#
# Break the workload in a known way, and record the truth before the agent sees it.
#
# The whole week rests on this script being honest. If the true cause is not
# written down BEFORE the investigation runs, then grading the agent afterwards
# is just deciding whether its story sounds plausible -- which is exactly the
# failure mode the week exists to examine.
#
# So this does three things in order:
#
#   1. writes down what it is about to do, with a timestamp
#   2. does exactly that and nothing else
#   3. records the CloudTrail-visible fact it produced
#
# THE BREAK
#
# Detach the `config-read` inline policy from the processor's execution role.
# The function reads an SSM parameter on every invocation; without
# ssm:GetParameter it throws AccessDeniedException.
#
# Chosen because every obvious place to look stays clean:
#   * no deployment    -- same code, same package hash
#   * no config change -- the parameter still exists, unchanged
#   * no infra change  -- the function, the schedule and the alarm are untouched
#
# The only evidence is one IAM event in CloudTrail, which is exactly what Week
# 15's attribution layer was built to find. That makes the agent's conclusion
# checkable against a fact rather than against an opinion.
#
# REVERSIBLE: scripts/fix_it.sh puts the policy back, or the next terraform
# apply does, since the policy is managed.

set -uo pipefail

# Git Bash mangles leading-slash arguments into Windows paths. Bit this repo on
# Week 12 and again on Week 15.
export MSYS_NO_PATHCONV=1

REGION="${AWS_REGION:-us-east-1}"
PREFIX="${NAME_PREFIX:-week16-agent}"
ROLE="${PREFIX}-processor"
POLICY="config-read"
LEDGER="${LEDGER_PATH:-docs/ground-truth.md}"

echo "Region : $REGION"
echo "Role   : $ROLE"
echo "Policy : $POLICY"
echo

###############################################################################
# 1. Confirm the workload is healthy first.
#
# Breaking something that was already broken produces an investigation with two
# causes and no way to tell which one the agent found.
###############################################################################
echo "--- 1. Confirming the workload is currently healthy ---"

if ! aws iam get-role-policy --role-name "$ROLE" --policy-name "$POLICY" \
     --region "$REGION" >/dev/null 2>&1; then
  echo "  ERROR: $POLICY is not attached to $ROLE."
  echo "  Either the break has already been run, or the stack is not deployed."
  echo "  Run scripts/fix_it.sh (or terraform apply) before breaking it again."
  exit 1
fi
echo "  ok: $POLICY is attached"

RECENT_ERRORS=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda --metric-name Errors \
  --dimensions "Name=FunctionName,Value=${PREFIX}-processor" \
  --start-time "$(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-30M +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 1800 --statistics Sum --region "$REGION" \
  --query "Datapoints[0].Sum" --output text 2>/dev/null)

if [[ "$RECENT_ERRORS" != "None" && "$RECENT_ERRORS" != "0.0" && -n "$RECENT_ERRORS" ]]; then
  echo "  WARN: the function already has $RECENT_ERRORS error(s) in the last 30 minutes."
  echo "        Investigate that first -- two overlapping causes make the grading meaningless."
fi

###############################################################################
# 2. Record the truth BEFORE breaking anything.
###############################################################################
BREAK_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
CALLER=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null)

mkdir -p "$(dirname "$LEDGER")"
{
  echo
  echo "## Break at ${BREAK_TIME}"
  echo
  echo "| | |"
  echo "|---|---|"
  echo "| **What was done** | Detached inline policy \`${POLICY}\` from role \`${ROLE}\` |"
  echo "| **Effect** | \`${PREFIX}-processor\` loses \`ssm:GetParameter\` and throws AccessDeniedException on every invocation |"
  echo "| **What did NOT change** | function code, package hash, environment variables, the SSM parameter itself, the schedule, the alarm |"
  echo "| **CloudTrail event** | \`DeleteRolePolicy\` on \`${ROLE}\` |"
  echo "| **Expected symptom** | Lambda Errors > 0 within ~5 minutes; alarm \`${PREFIX}-processor-errors\` to ALARM |"
  echo
  echo "**Grade the agent against this.** A correct answer names the policy"
  echo "detachment. Naming the AccessDeniedException is the symptom, not the cause,"
  echo "and should be marked as such."
  echo
} >> "$LEDGER"

echo
echo "--- 2. Ground truth recorded ---"
echo "  $LEDGER"
echo "  break time: $BREAK_TIME"

###############################################################################
# 3. Break it.
###############################################################################
echo
echo "--- 3. Detaching $POLICY ---"

# Note: no 2>&1 suppression. Week 15's activity script hid a completely failed
# run behind soft WARN lines, and a break that silently did not happen would
# invalidate everything downstream.
if aws iam delete-role-policy --role-name "$ROLE" --policy-name "$POLICY" --region "$REGION"; then
  echo "  DETACHED. The workload is now broken."
else
  echo "  FAILED to detach -- nothing was broken. Fix the error above and retry."
  echo "  (The ground-truth entry above is now inaccurate; delete it.)"
  exit 1
fi

cat <<EOF

Done.

  broken at : ${BREAK_TIME}
  by        : ${CALLER}

What happens next, and roughly when:

  ~5 min   the scheduled invocation fails, Lambda Errors goes above zero
  ~5-10min alarm ${PREFIX}-processor-errors enters ALARM
  then     the agent has something to investigate

Before asking the agent anything, take a usage reading:

  ./scripts/measure_usage.sh

Take another one afterwards. The difference is what the investigation cost --
this service has no spend ceiling, so measuring is the only control there is.

To undo:

  ./scripts/fix_it.sh
EOF
