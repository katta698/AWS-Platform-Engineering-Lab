#!/usr/bin/env bash
#
# Undo the deliberate break.
#
# Separate from terraform apply on purpose. An apply would also reconcile
# anything else that drifted, which muddies the timeline the agent is being
# graded on -- the point is to restore exactly what was removed and nothing
# else, so the CloudTrail record of the repair is as clean as the record of
# the break.

set -uo pipefail
export MSYS_NO_PATHCONV=1

REGION="${AWS_REGION:-us-east-1}"
PREFIX="${NAME_PREFIX:-week16-agent}"
ROLE="${PREFIX}-processor"
POLICY="config-read"
LEDGER="${LEDGER_PATH:-docs/ground-truth.md}"

PARAM_ARN=$(aws ssm get-parameter --name "/${PREFIX}/processing-mode" --region "$REGION" \
  --query "Parameter.ARN" --output text 2>/dev/null)

if [[ -z "$PARAM_ARN" || "$PARAM_ARN" == "None" ]]; then
  echo "ERROR: could not resolve the SSM parameter ARN -- is the stack deployed?" >&2
  exit 1
fi

echo "Restoring $POLICY on $ROLE..."
aws iam put-role-policy --role-name "$ROLE" --policy-name "$POLICY" --region "$REGION" \
  --policy-document "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Action\":[\"ssm:GetParameter\"],\"Resource\":\"${PARAM_ARN}\"}]}"

if [[ $? -ne 0 ]]; then
  echo "FAILED to restore the policy." >&2
  exit 1
fi

FIX_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
{
  echo "**Repaired at ${FIX_TIME}** — \`${POLICY}\` restored on \`${ROLE}\`."
  echo
} >> "$LEDGER"

cat <<MSG
  RESTORED at ${FIX_TIME}

IAM changes take a moment to reach Lambda. The next scheduled run (within ~5
minutes) should succeed, and the alarm returns to OK shortly after -- it uses a
5-minute period precisely so it recovers rather than latching, which is the
Week 15 defect this build avoids by design.
MSG
