#!/usr/bin/env bash
###############################################################################
# deploy.sh — Local deploy for Week 2: Aurora Self-Service Platform
###############################################################################
set -euo pipefail

ENVIRONMENT="${1:-dev}"
REGION="${2:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_ROOT/terraform/environments/$ENVIRONMENT"
TFVARS="$TF_DIR/terraform.tfvars"

if [ ! -f "$TFVARS" ]; then
  echo "❌  terraform.tfvars not found at $TFVARS"
  echo "    Copy terraform.tfvars.example → terraform.tfvars and fill values."
  exit 1
fi

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# ── Pre-flight: clear orphaned CloudWatch log groups ──────────────────────────
echo -e "${YELLOW}▶  Pre-flight: clearing orphaned CloudWatch log groups...${NC}"
for LOG_GROUP in \
  "/aws/lambda/selfservice-db-${ENVIRONMENT}-webhook-receiver" \
  "/aws/lambda/selfservice-db-${ENVIRONMENT}-db-provisioner" \
  "/aws/lambda/selfservice-db-${ENVIRONMENT}-status-updater" \
  "/aws/lambda/selfservice-db-${ENVIRONMENT}-secret-rotation" \
  "/aws/states/selfservice-db-${ENVIRONMENT}-db-provisioning"; do
  MSYS_NO_PATHCONV=1 aws logs delete-log-group \
    --log-group-name "$LOG_GROUP" \
    --region "$REGION" 2>/dev/null \
    && echo "   Deleted: $LOG_GROUP" \
    || echo "   Not found (OK): $LOG_GROUP"
done

cd "$TF_DIR"

echo ""
echo -e "${YELLOW}▶  terraform init...${NC}"
terraform init -reconfigure

echo ""
echo -e "${YELLOW}▶  terraform plan...${NC}"
terraform plan -var-file="terraform.tfvars" -out=tfplan

echo ""
read -rp "Apply the plan? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

echo ""
echo -e "${YELLOW}▶  terraform apply...${NC}"
terraform apply tfplan

echo ""
echo -e "${GREEN}✅ Deploy complete!${NC}"
echo ""
terraform output
