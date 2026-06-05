#!/usr/bin/env bash
###############################################################################
# cleanup.sh — Destroy all Week 3 infrastructure + CloudWatch log groups
###############################################################################
set -euo pipefail

ENVIRONMENT="${1:-dev}"
REGION="${2:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_ROOT/terraform/environments/$ENVIRONMENT"
RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${RED}WARNING: This will DESTROY all Week 3 infrastructure in '$ENVIRONMENT'${NC}"
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
  -var="alert_email=dummy@example.com" \
  -var="webhook_secret=dummy" \
  -var="servicenow_instance_url=https://dummy.service-now.com" \
  -var="servicenow_username=dummy" \
  -var="servicenow_password=dummy"

# Post-destroy: delete CloudWatch log groups
echo ""
echo "Cleaning up CloudWatch log groups..."
for LOG_GROUP in \
  "/aws/lambda/ssm-fleet-${ENVIRONMENT}-webhook-receiver" \
  "/aws/lambda/ssm-fleet-${ENVIRONMENT}-fleet-onboarder" \
  "/aws/lambda/ssm-fleet-${ENVIRONMENT}-patch-orchestrator" \
  "/aws/lambda/ssm-fleet-${ENVIRONMENT}-status-updater" \
  "/aws/states/ssm-fleet-${ENVIRONMENT}-fleet-management" \
  "/aws/ssm/ssm-fleet-${ENVIRONMENT}/sessions"; do
  MSYS_NO_PATHCONV=1 aws logs delete-log-group \
    --log-group-name "$LOG_GROUP" \
    --region "$REGION" 2>/dev/null \
    && echo "  Deleted: $LOG_GROUP" \
    || echo "  Not found (OK): $LOG_GROUP"
done

echo ""
echo -e "${YELLOW}Week 3 infrastructure destroyed.${NC}"
echo "  S3 state bucket retained (reused across weeks)"
echo "  OIDC provider retained (shared)"
echo "  SSM documents deleted with Terraform"
echo "  Session logs S3 bucket deleted (force_destroy=true)"
