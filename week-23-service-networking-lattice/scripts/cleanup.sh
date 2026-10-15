#!/usr/bin/env bash
# Run AFTER terraform destroy. Verifies the teardown.
#
#   bash scripts/cleanup.sh
#
# Week 22's lesson applied: check rather than assume. There, terraform destroy
# genuinely had removed the account-level settings, and the script confirmed it
# instead of guessing. The same approach here, with one addition specific to
# Lattice: a VPC cannot be deleted while a service network association survives,
# so a half-finished destroy leaves a VPC that looks orphaned and is not.

set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
PREFIX="${NAME_PREFIX:-week23-lattice}"

echo
echo "== 1. Service networks =="
NETS=$(aws vpc-lattice list-service-networks --region "$REGION" \
        --query "items[?starts_with(name,'${PREFIX}')].[name,id]" --output text 2>/dev/null)
if [ -z "$NETS" ]; then echo "   none remaining"; else
  echo "$NETS" | while read -r n i; do
    [ -z "$n" ] && continue
    echo "   STILL PRESENT: $n ($i)"
  done
fi

echo
echo "== 2. Services =="
SVCS=$(aws vpc-lattice list-services --region "$REGION" \
        --query "items[?starts_with(name,'${PREFIX}')].[name,id]" --output text 2>/dev/null)
echo "   ${SVCS:-none remaining}"

echo
echo "== 3. Service network VPC associations =="
# These are free, which is exactly why they get forgotten. They also block the
# VPC from being deleted.
ASSOC=$(aws vpc-lattice list-service-network-vpc-associations --region "$REGION" \
         --query 'items[].[id,status]' --output text 2>/dev/null)
echo "   ${ASSOC:-none remaining}"

echo
echo "== 4. Target groups =="
TGS=$(aws vpc-lattice list-target-groups --region "$REGION" \
       --query "items[?starts_with(name,'${PREFIX}')].[name,status]" --output text 2>/dev/null)
echo "   ${TGS:-none remaining}"

echo
echo "== 5. The consumer VPC =="
VPCS=$(aws ec2 describe-vpcs --region "$REGION" \
        --filters "Name=tag:Name,Values=${PREFIX}-consumer" \
        --query 'Vpcs[].VpcId' --output text 2>/dev/null)
echo "   ${VPCS:-none remaining}"

echo
echo "== 6. Lambda functions and log groups =="
FNS=$(aws lambda list-functions --region "$REGION" \
       --query "Functions[?starts_with(FunctionName,'${PREFIX}')].FunctionName" --output text 2>/dev/null)
echo "   functions:  ${FNS:-none remaining}"
LGS=$(aws logs describe-log-groups --region "$REGION" \
       --log-group-name-prefix "/aws/lambda/${PREFIX}" \
       --query 'logGroups[].logGroupName' --output text 2>/dev/null)
echo "   log groups: ${LGS:-none remaining}"

echo
echo "== 7. IAM roles =="
ROLES=$(aws iam list-roles --query "Roles[?starts_with(RoleName,'${PREFIX}')].RoleName" --output text 2>/dev/null)
echo "   ${ROLES:-none remaining}"

echo
echo "-----------------------------------------------------------"
echo "Teardown checked. Not verifiable today:"
echo "  - the bill. Read it tomorrow, grouped by USAGE_TYPE."
echo "    Grouping by service only says 'VPC Lattice' and hides"
echo "    which dimension actually cost anything."
echo "-----------------------------------------------------------"
