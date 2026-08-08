#!/usr/bin/env bash
#
# Week 13 teardown.
#
# The HCP workspace week-13-dev is VCS-connected, which means `terraform
# destroy` from a CLI checkout will not run against it. Destroy from the HCP
# UI instead: Workspace -> Settings -> Destruction and Deletion -> Queue
# destroy plan.
#
# This script only verifies that the destroy actually removed everything, and
# reports anything left behind. WAF web ACLs and CloudFront distributions are
# the two things most likely to linger, for opposite reasons: a web ACL cannot
# be deleted while still associated with a resource, and a CloudFront
# distribution must be disabled and fully propagated before it can be removed,
# which takes roughly 15 minutes.

set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
PREFIX="week13-waf"

echo "Checking for surviving Week 13 resources..."
echo

fail=0

# Distinguishes three outcomes, not two. The original version swallowed
# stderr and treated any empty result as "gone" -- which meant an expired
# SSO session, a permissions error or a typo'd query all reported a clean
# teardown while having verified nothing at all. A teardown check that can
# pass without checking is worse than no check.
check() {
  local label="$1"
  shift
  local out rc
  out=$("$@" 2>&1); rc=$?

  if [[ $rc -ne 0 ]]; then
    echo "  ERROR          $label -- could not verify"
    echo "$out" | head -2 | sed 's/^/                 /'
    fail=1
  elif [[ -n "$out" && "$out" != "None" ]]; then
    echo "  STILL PRESENT  $label"
    echo "$out" | sed 's/^/                 /'
    fail=1
  else
    echo "  gone           $label"
  fi
}

check "Web ACLs (REGIONAL, $REGION)" \
  aws wafv2 list-web-acls --scope REGIONAL --region "$REGION" \
  --query "WebACLs[?starts_with(Name, '$PREFIX')].Name" --output text

check "Web ACLs (CLOUDFRONT, us-east-1)" \
  aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 \
  --query "WebACLs[?starts_with(Name, '$PREFIX')].Name" --output text

check "IP sets (REGIONAL, $REGION)" \
  aws wafv2 list-ip-sets --scope REGIONAL --region "$REGION" \
  --query "IPSets[?starts_with(Name, '$PREFIX')].Name" --output text

check "CloudFront distributions" \
  aws cloudfront list-distributions \
  --query "DistributionList.Items[?contains(Comment, '$PREFIX')].Id" --output text

check "API Gateway REST APIs" \
  aws apigateway get-rest-apis --region "$REGION" \
  --query "items[?starts_with(name, '$PREFIX')].name" --output text

check "Lambda functions" \
  aws lambda list-functions --region "$REGION" \
  --query "Functions[?starts_with(FunctionName, '$PREFIX')].FunctionName" --output text

# Log groups outlive the resources that wrote to them and quietly keep costing
# money, so they are worth checking explicitly rather than assuming.
echo
echo "Log groups (deleted with the stack, but verify -- these outlive their source):"
MSYS_NO_PATHCONV=1 aws logs describe-log-groups --region "$REGION" \
  --log-group-name-prefix "aws-waf-logs-$PREFIX" \
  --query 'logGroups[].logGroupName' --output text 2>/dev/null | sed 's/^/  /'
MSYS_NO_PATHCONV=1 aws logs describe-log-groups --region us-east-1 \
  --log-group-name-prefix "aws-waf-logs-$PREFIX" \
  --query 'logGroups[].logGroupName' --output text 2>/dev/null | sed 's/^/  /'

check "SNS topics" \
  aws sns list-topics --region "$REGION" \
  --query "Topics[?contains(TopicArn, '$PREFIX')].TopicArn" --output text

check "CloudWatch alarms" \
  aws cloudwatch describe-alarms --alarm-name-prefix "$PREFIX" --region "$REGION" \
  --query 'MetricAlarms[].AlarmName' --output text

check "IAM roles" \
  aws iam list-roles \
  --query "Roles[?starts_with(RoleName, '$PREFIX')].RoleName" --output text

echo
echo "Reminder: Shield Standard needs no teardown. It was never provisioned"
echo "and remains active on the account at no charge."
echo

if [[ $fail -ne 0 ]]; then
  echo "RESULT: NOT clean -- see the ERROR/STILL PRESENT lines above."
  echo "An ERROR line means the check could not run (expired SSO session is the"
  echo "usual cause: run 'aws sso login' and re-run this script). Do not read a"
  echo "failed check as a successful teardown."
  exit 1
fi

echo "RESULT: clean -- every check ran and found nothing."
