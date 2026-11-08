#!/usr/bin/env bash
# Destroy week 26, then verify it rather than trusting the destroy output.
#
# DAX bills per node-hour from the moment the cluster is available, so this
# is the script that decides what the week costs. A destroy reports what
# Terraform removed, not what is left in the account, so the cluster and the
# table are both checked afterwards against the API.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
REGION="${AWS_REGION:-us-east-1}"
NAME="week26-tenant-isolation"

cd "$ROOT/terraform/environments/dev"

# Plan the destroy first and apply that plan, rather than destroying blind.
# The plan says exactly what is going, which matters when the thing being
# removed is the only resource on the account billing by the hour.
echo "==> planning the destroy"
terraform plan -destroy -input=false -out=wk26-destroy.tfplan

echo
echo "==> applying it"
terraform apply -input=false wk26-destroy.tfplan
rm -f wk26-destroy.tfplan

echo
echo "==> verifying against the API, not the destroy output"
rc=0

if aws dax describe-clusters --cluster-names "$DAX_NAME" --region "$REGION" \
     >/dev/null 2>&1; then
  echo "  STILL PRESENT  dax cluster $DAX_NAME -- this is still billing"
  rc=1
else
  echo "  gone           dax cluster $DAX_NAME"
fi

if aws dynamodb describe-table --table-name "${NAME}-pool" --region "$REGION" \
     >/dev/null 2>&1; then
  echo "  STILL PRESENT  dynamodb table ${NAME}-pool"
  rc=1
else
  echo "  gone           dynamodb table ${NAME}-pool"
fi

left=$(aws lambda list-functions --region "$REGION" \
         --query "length(Functions[?starts_with(FunctionName, '${NAME}')])" \
         --output text 2>/dev/null || echo 0)
if [ "$left" != "0" ]; then
  echo "  STILL PRESENT  $left lambda function(s) named ${NAME}-*"
  rc=1
else
  echo "  gone           lambda functions"
fi

echo
if [ "$rc" -ne 0 ]; then
  echo "TEARDOWN INCOMPLETE -- something above is still in the account."
  exit 1
fi
echo "Teardown verified: nothing from week 26 remains in $REGION."
