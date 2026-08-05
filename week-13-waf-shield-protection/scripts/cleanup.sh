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

check() {
  local label="$1"
  shift
  local out
  out=$("$@" 2>/dev/null)
  if [[ -n "$out" && "$out" != "None" ]]; then
    echo "  STILL PRESENT  $label"
    echo "$out" | sed 's/^/                 /'
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

echo
echo "Reminder: Shield Standard needs no teardown. It was never provisioned"
echo "and remains active on the account at no charge."
