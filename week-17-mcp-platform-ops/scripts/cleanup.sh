#!/usr/bin/env bash
# Verify Week 17 is really gone. Run AFTER the HCP destroy, not instead of it.
#
# A destroy run reporting "applied" says Terraform removed what it knew about.
# It says nothing about resources a script created outside Terraform -- which is
# how two Week 12 test buckets survived their teardown. Every check below asks
# AWS directly.
set -uo pipefail
PROFILE="${AWS_PROFILE:-personal}"
PREFIX="week17"
fail=0

check() {
  local label="$1" result="$2"
  if [[ -z "$result" || "$result" == "[]" || "$result" == "None" ]]; then
    printf '  [gone] %s\n' "$label"
  else
    printf '  [LIVE] %s -> %s\n' "$label" "$result"; fail=1
  fi
}

echo "Week 17 teardown verification"
check "lambda functions"  "$(aws lambda list-functions --profile "$PROFILE" \
  --query "Functions[?starts_with(FunctionName,'${PREFIX}')].FunctionName" --output text)"
check "iam roles"         "$(aws iam list-roles --profile "$PROFILE" \
  --query "Roles[?starts_with(RoleName,'${PREFIX}')].RoleName" --output text)"
check "dynamodb tables"   "$(aws dynamodb list-tables --profile "$PROFILE" \
  --query "TableNames[?starts_with(@,'${PREFIX}')]" --output text)"
check "cloudwatch alarms" "$(aws cloudwatch describe-alarms --profile "$PROFILE" \
  --alarm-name-prefix "$PREFIX" --query "MetricAlarms[].AlarmName" --output text)"
check "log groups"        "$(aws logs describe-log-groups --profile "$PROFILE" \
  --query "logGroups[?contains(logGroupName,'${PREFIX}')].logGroupName" --output text)"

# Tag search catches anything the name prefix misses.
check "tagged Week=17"    "$(aws resourcegroupstaggingapi get-resources --profile "$PROFILE" \
  --tag-filters Key=Week,Values=17 --query "ResourceTagMappingList[].ResourceARN" --output text)"

echo
if [[ $fail -eq 0 ]]; then
  echo "CLEAN — nothing from Week 17 remains."
else
  echo "NOT CLEAN — see [LIVE] lines above."; exit 1
fi
