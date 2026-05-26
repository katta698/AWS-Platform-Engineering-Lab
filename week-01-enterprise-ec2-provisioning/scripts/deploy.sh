#!/usr/bin/env bash
###############################################################################
# deploy.sh — Local deploy script for cost-managed lab sessions
# Usage: sh scripts/deploy.sh [environment] [region]
# Example: sh scripts/deploy.sh dev us-east-1
###############################################################################
set -euo pipefail

ENVIRONMENT="${1:-dev}"
REGION="${2:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TF_DIR="$PROJECT_ROOT/terraform/environments/$ENVIRONMENT"

# ── Load tfvars ──────────────────────────────────────────────────────────────
TFVARS="$PROJECT_ROOT/terraform/environments/$ENVIRONMENT/terraform.tfvars"
if [ ! -f "$TFVARS" ]; then
  echo "❌  terraform.tfvars not found at $TFVARS"
  echo "    Create it with your secrets before deploying."
  exit 1
fi

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${YELLOW}🚀 Deploying environment: $ENVIRONMENT${NC}"
echo ""

cd "$TF_DIR"

# ── Init ─────────────────────────────────────────────────────────────────────
echo "▶  terraform init..."
terraform init -reconfigure

# ── Pre-flight: delete orphaned log groups that survive terraform destroy ──────
# CloudWatch log groups persist after destroy if they contain log data.
# Terraform has no "adopt existing resource" option, so we delete them first.
echo ""
echo "▶  Pre-flight: clearing orphaned CloudWatch log groups..."
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

# ── Plan ─────────────────────────────────────────────────────────────────────
echo ""
echo "▶  terraform plan..."
terraform plan \
  -var-file="terraform.tfvars" \
  -out=tfplan

# ── Confirm ──────────────────────────────────────────────────────────────────
echo ""
read -rp "Apply the plan? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Aborted."
  exit 0
fi

# ── Apply ─────────────────────────────────────────────────────────────────────
echo ""
echo "▶  terraform apply..."
terraform apply tfplan

echo ""
echo -e "${GREEN}✅ Deploy complete!${NC}"
echo ""
echo "Outputs:"
terraform output
