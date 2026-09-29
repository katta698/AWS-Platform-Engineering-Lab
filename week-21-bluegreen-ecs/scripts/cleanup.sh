#!/usr/bin/env bash
# Week 21 teardown verification. Run AFTER the HCP destroy.
#
# This week has a real hourly meter -- the ALB bills whether or not anything is
# deployed -- so "probably gone" is not good enough.
#
# One lesson carried in deliberately: a check that cries wolf is one nobody
# reads to the end. Anything that cannot be deleted and does not bill is
# reported as a note, not a finding.
set -uo pipefail

PREFIX="${PREFIX:-week21-bluegreen}"
PROFILE="${AWS_PROFILE:-personal}"
aws_() { MSYS_NO_PATHCONV=1 aws --profile "$PROFILE" "$@"; }

live=0
check() {
  if [[ -z "${2//[[:space:]]/}" || "$2" == "None" || "$2" == "0" ]]; then
    printf '  [gone] %s\n' "$1"
  else
    printf '  [LIVE] %s -> %s\n' "$1" "$2"; live=1
  fi
}

echo "Week 21 teardown verification"

check "ecs services"   "$(aws_ ecs list-services --cluster "$PREFIX" --query 'length(serviceArns)' --output text 2>/dev/null)"
check "ecs clusters"   "$(aws_ ecs list-clusters --query "clusterArns[?contains(@,'${PREFIX}')]" --output text)"
check "running tasks"  "$(aws_ ecs list-tasks --cluster "$PREFIX" --query 'length(taskArns)' --output text 2>/dev/null)"
check "load balancers" "$(aws_ elbv2 describe-load-balancers --query "LoadBalancers[?contains(LoadBalancerName,'${PREFIX}')].LoadBalancerName" --output text)"
check "target groups"  "$(aws_ elbv2 describe-target-groups --query "TargetGroups[?contains(TargetGroupName,'${PREFIX}')].TargetGroupName" --output text)"
check "task definitions (ACTIVE)" "$(aws_ ecs list-task-definitions --family-prefix "$PREFIX" --status ACTIVE --query 'length(taskDefinitionArns)' --output text 2>/dev/null)"
check "alarms"         "$(aws_ cloudwatch describe-alarms --alarm-name-prefix "$PREFIX" --query 'length(MetricAlarms)' --output text)"
check "log groups"     "$(aws_ logs describe-log-groups --log-group-name-prefix "/ecs/${PREFIX}" --query 'length(logGroups)' --output text)"
check "security groups" "$(aws_ ec2 describe-security-groups --filters "Name=group-name,Values=${PREFIX}*" --query 'length(SecurityGroups)' --output text)"
check "iam roles"      "$(aws_ iam list-roles --query "Roles[?starts_with(RoleName,'${PREFIX}')].RoleName" --output text)"

echo
if (( live )); then
  echo "NOT CLEAN - see [LIVE] lines above."
  echo "The ALB is the one that matters: it bills hourly with no traffic at all."
  exit 1
fi
echo "CLEAN - nothing from Week 21 remains."
