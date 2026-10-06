#!/usr/bin/env bash
# Run AFTER terraform destroy. Verifies the teardown and removes what destroy
# does not.
#
#   bash scripts/cleanup.sh
#
# Why this exists: Amazon Inspector is enabled per ACCOUNT, not per stack. In
# Week 14 a CloudWatch anomaly detector survived terraform destroy and kept
# billing for days, because it was an account-level setting that no resource
# owned. Inspector is the same shape of risk and gets the same treatment:
# assume it survived, check, and read the bill tomorrow.

set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
PREFIX="${FILTER_PREFIX:-wk22}"

echo
echo "== 1. Registry scanning configuration =="
SCAN=$(aws ecr get-registry-scanning-configuration --region "$REGION" \
        --query 'scanningConfiguration.scanType' --output text 2>/dev/null)
echo "   scanType: ${SCAN:-unknown}"
if [ "$SCAN" = "ENHANCED" ]; then
  echo "   still ENHANCED -- resetting to BASIC"
  aws ecr put-registry-scanning-configuration --region "$REGION" --scan-type BASIC >/dev/null 2>&1 \
    && echo "   reset to BASIC" || echo "   WARNING: could not reset" >&2
fi

echo
echo "== 2. Amazon Inspector (separate service, separate bill) =="
for t in ec2 ecr lambda lambdaCode codeRepository; do
  S=$(aws inspector2 batch-get-account-status --region "$REGION" \
       --query "accounts[0].resourceState.${t}.status" --output text 2>/dev/null)
  echo "   ${t}: ${S:-unknown}"
done
ECR_S=$(aws inspector2 batch-get-account-status --region "$REGION" \
         --query 'accounts[0].resourceState.ecr.status' --output text 2>/dev/null)
if [ "$ECR_S" = "ENABLED" ]; then
  echo "   ECR scanning still ENABLED -- disabling"
  ACCT=$(aws sts get-caller-identity --query Account --output text)
  aws inspector2 disable --region "$REGION" --account-ids "$ACCT" --resource-types ECR >/dev/null 2>&1 \
    && echo "   disabled" || echo "   WARNING: could not disable -- do it in the Inspector console" >&2
fi

echo
echo "== 3. ECR repositories =="
LEFT=$(aws ecr describe-repositories --region "$REGION" \
        --query "repositories[?starts_with(repositoryName, '${PREFIX}') || starts_with(repositoryName, 'outside-filter')].repositoryName" \
        --output text 2>/dev/null)
if [ -z "$LEFT" ]; then echo "   none remaining"; else
  echo "   still present: $LEFT"
  for r in $LEFT; do
    aws ecr delete-repository --region "$REGION" --repository-name "$r" --force >/dev/null 2>&1 \
      && echo "   deleted $r" || echo "   WARNING: could not delete $r" >&2
  done
fi

echo
echo "== 4. Signer signing profiles =="
# Signer profiles cannot be deleted, only CANCELLED. A cancelled profile costs
# nothing and cannot sign; this is the documented end state, not a leftover.
PROFS=$(aws signer list-signing-profiles --region "$REGION" \
         --query "profiles[?starts_with(profileName, 'wk22_')].[profileName,status]" --output text 2>/dev/null)
if [ -z "$PROFS" ]; then echo "   none active"; else
  echo "$PROFS" | while read -r name status; do
    [ -z "$name" ] && continue
    echo "   $name: $status"
    if [ "$status" = "Active" ]; then
      aws signer cancel-signing-profile --region "$REGION" --profile-name "$name" >/dev/null 2>&1 \
        && echo "     cancelled" || echo "     WARNING: could not cancel" >&2
    fi
  done
fi

echo
echo "== 5. Signing configuration =="
SC=$(aws ecr get-signing-configuration --region "$REGION" --output json 2>&1)
if echo "$SC" | grep -qi "rules"; then
  echo "   a signing configuration still exists:"
  echo "$SC" | head -12 | sed 's/^/     /'
  echo "   removing"
  aws ecr delete-signing-configuration --region "$REGION" >/dev/null 2>&1 \
    && echo "   removed" || echo "   WARNING: could not remove" >&2
else
  echo "   none"
fi

echo
echo "== 6. Log groups =="
LG=$(aws logs describe-log-groups --region "$REGION" \
      --log-group-name-prefix "/aws/lambda/week22" \
      --query 'logGroups[].logGroupName' --output text 2>/dev/null)
echo "   ${LG:-none remaining}"

echo
echo "-----------------------------------------------------------"
echo "Teardown checked. Two things are NOT verifiable today:"
echo "  - the bill. Read it tomorrow; Inspector charges land late."
echo "  - the Inspector free trial. It is consumed once started,"
echo "    whatever you do next. Note the date in the README."
echo "-----------------------------------------------------------"
