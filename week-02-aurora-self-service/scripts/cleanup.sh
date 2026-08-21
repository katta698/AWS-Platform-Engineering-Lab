#!/usr/bin/env bash
###############################################################################
# cleanup.sh — Destroy all Week 2 infrastructure + CloudWatch log groups
###############################################################################
set -euo pipefail


# The account ID is resolved at runtime rather than hardcoded. It is only needed
# to satisfy a required variable during destroy -- the destroy targets whatever
# account the caller is already authenticated to, so any other value would be
# wrong anyway. Resolving it also keeps the account ID out of this repository.
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
if [[ -z "$AWS_ACCOUNT_ID" || "$AWS_ACCOUNT_ID" == "None" ]]; then
  echo "ERROR: could not resolve the AWS account ID -- are your credentials valid?" >&2
  exit 1
fi

ENVIRONMENT="${1:-dev}"
REGION="${2:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_ROOT/terraform/environments/$ENVIRONMENT"
RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${RED}⚠  WARNING: This will DESTROY all Week 2 infrastructure in '$ENVIRONMENT'${NC}"
echo ""
read -rp "Type the environment name to confirm: " CONFIRM

if [ "$CONFIRM" != "$ENVIRONMENT" ]; then
  echo "Confirmation does not match. Aborting."
  exit 1
fi

echo ""
echo "Proceeding with cleanup of $ENVIRONMENT..."

cd "$TF_DIR"

terraform init

terraform destroy -auto-approve \
  -var="master_password=dummy" \
  -var="alert_email=dummy@example.com" \
  -var="pg8000_layer_arn=arn:aws:lambda:us-east-1:000000000000:layer:dummy:1" \
  -var="servicenow_instance_url=https://dummy.service-now.com" \
  -var="servicenow_username=dummy" \
  -var="servicenow_password=dummy" \
  -var="webhook_secret=dummy" \
  -var="github_org=dummy" \
  -var="github_repo=dummy" \
  -var="github_token=dummy" \
  -var="create_github_oidc_provider=false" \
  -var="existing_oidc_provider_arn=arn:aws:iam::${AWS_ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

# ── Post-destroy: delete CloudWatch log groups ────────────────────────────────
echo ""
echo "▶  Cleaning up CloudWatch log groups..."
for LOG_GROUP in \
  "/aws/lambda/selfservice-db-${ENVIRONMENT}-webhook-receiver" \
  "/aws/lambda/selfservice-db-${ENVIRONMENT}-db-provisioner" \
  "/aws/lambda/selfservice-db-${ENVIRONMENT}-status-updater" \
  "/aws/lambda/selfservice-db-${ENVIRONMENT}-secret-rotation" \
  "/aws/states/selfservice-db-${ENVIRONMENT}-db-provisioning" \
  "/aws/rds/cluster/selfservice-db-${ENVIRONMENT}-aurora/postgresql"; do
  MSYS_NO_PATHCONV=1 aws logs delete-log-group \
    --log-group-name "$LOG_GROUP" \
    --region "$REGION" 2>/dev/null \
    && echo "   Deleted: $LOG_GROUP" \
    || echo "   Not found (OK): $LOG_GROUP"
done

echo ""
echo -e "${YELLOW}✅ Week 2 infrastructure destroyed.${NC}"
echo "  S3 state bucket retained (reused across weeks)"
echo "  OIDC provider retained (shared with Week 1)"
echo "  pg8000 Lambda layer retained (delete manually if desired)"
