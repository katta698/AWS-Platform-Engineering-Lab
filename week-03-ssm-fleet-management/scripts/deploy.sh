#!/usr/bin/env bash
###############################################################################
# deploy.sh — Deploy Week 3 SSM Fleet Management
###############################################################################
set -euo pipefail

ENVIRONMENT="${1:-dev}"
REGION="${2:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_ROOT/terraform/environments/$ENVIRONMENT"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${YELLOW}Week 3: SSM Fleet Management — deploying to '$ENVIRONMENT'${NC}"
echo ""

# Pre-flight: delete orphaned CloudWatch log groups
echo "Cleaning up any orphaned log groups..."
for LOG_GROUP in \
  "/aws/lambda/fleet-mgmt-${ENVIRONMENT}-webhook-receiver" \
  "/aws/lambda/fleet-mgmt-${ENVIRONMENT}-fleet-onboarder" \
  "/aws/lambda/fleet-mgmt-${ENVIRONMENT}-patch-orchestrator" \
  "/aws/lambda/fleet-mgmt-${ENVIRONMENT}-status-updater" \
  "/aws/states/fleet-mgmt-${ENVIRONMENT}-fleet-management" \
  "/aws/ssm/fleet-mgmt-${ENVIRONMENT}/sessions"; do
  MSYS_NO_PATHCONV=1 aws logs delete-log-group \
    --log-group-name "$LOG_GROUP" \
    --region "$REGION" 2>/dev/null \
    && echo "  Deleted: $LOG_GROUP" \
    || true
done

cd "$TF_DIR"

if [ ! -f "terraform.tfvars" ]; then
  echo ""
  echo "ERROR: terraform.tfvars not found."
  echo "Copy the example file and fill in your values:"
  echo "  cp terraform.tfvars.example terraform.tfvars"
  exit 1
fi

terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan

echo ""
echo -e "${GREEN}Deployment complete!${NC}"
echo ""
terraform output
echo ""
echo "Next steps:"
echo "  1. Check SSM Fleet Manager — instances should appear within ~5 min"
echo "  2. Update ServiceNow Outbound REST Message with API URL above"
echo "  3. Test with: curl -X POST \"\$(terraform output -raw api_gateway_url)\" \\"
echo "       -H 'Content-Type: application/json' \\"
echo "       -d '{\"ticket_id\":\"RITM0020001\",\"request_type\":\"patch\",\"patch_group\":\"fleet-mgmt-${ENVIRONMENT}-linux\",\"operation\":\"Scan\"}'"
