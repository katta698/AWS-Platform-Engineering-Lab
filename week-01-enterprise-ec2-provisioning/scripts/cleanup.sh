#!/usr/bin/env bash
###############################################################################
# cleanup.sh — Safe environment teardown script
# Always run this for cost management when done learning
###############################################################################
set -euo pipefail

ENVIRONMENT="${1:-dev}"
REGION="${2:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_ROOT/terraform/environments/$ENVIRONMENT"
RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${RED}⚠  WARNING: This will DESTROY all infrastructure in '$ENVIRONMENT'${NC}"
echo ""
read -rp "Type the environment name to confirm: " CONFIRM

if [ "$CONFIRM" != "$ENVIRONMENT" ]; then
  echo "Confirmation does not match. Aborting."
  exit 1
fi

echo ""
echo "Proceeding with cleanup of $ENVIRONMENT..."

cd "$TF_DIR"

terraform init \
  -backend-config="region=$REGION"

terraform destroy -auto-approve \
  -var="artifact_bucket_name=dummy" \
  -var="tf_state_bucket=jay-terraformstate-bucket" \
  -var="github_org=dummy" \
  -var="github_repo=dummy" \
  -var="github_token=dummy" \
  -var="servicenow_instance_url=https://dummy.service-now.com" \
  -var="servicenow_username=dummy" \
  -var="servicenow_password=dummy" \
  -var="webhook_secret=dummy" \
  -var="create_github_oidc_provider=false" \
  -var="existing_oidc_provider_arn=arn:aws:iam::684346483786:oidc-provider/token.actions.githubusercontent.com"

# ── Post-destroy: delete CloudWatch log groups (AWS retains them after destroy) ─
echo ""
echo "▶  Cleaning up CloudWatch log groups..."
for LOG_GROUP in \
  "/aws/vpc/selfservice-ec2-${ENVIRONMENT}-flow-logs" \
  "/aws/lambda/selfservice-ec2-${ENVIRONMENT}-webhook" \
  "/aws/lambda/selfservice-ec2-${ENVIRONMENT}-orchestrator" \
  "/aws/lambda/selfservice-ec2-${ENVIRONMENT}-callback"; do
  MSYS_NO_PATHCONV=1 aws logs delete-log-group \
    --log-group-name "$LOG_GROUP" \
    --region "$REGION" 2>/dev/null \
    && echo "   Deleted: $LOG_GROUP" \
    || echo "   Not found (OK): $LOG_GROUP"
done

echo ""
echo -e "${YELLOW}✅ Infrastructure destroyed. Remember to also:${NC}"
echo "  1. Delete the S3 state bucket manually if no longer needed"
echo "  2. Delete the DynamoDB lock table if not shared"
echo "  3. Revoke GitHub OIDC trust if no longer needed"
