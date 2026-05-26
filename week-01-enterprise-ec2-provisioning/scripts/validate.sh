#!/usr/bin/env bash
###############################################################################
# validate.sh — Post-deployment validation script
# Run this after Terraform apply to verify the environment is healthy
###############################################################################
set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
ENVIRONMENT="${1:-dev}"
REGION="${2:-us-east-1}"
TF_DIR="terraform/environments/$ENVIRONMENT"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'

pass() { echo -e "${GREEN}✅ PASS${NC}: $1"; }
fail() { echo -e "${RED}❌ FAIL${NC}: $1"; FAILURES=$((FAILURES+1)); }
info() { echo -e "${YELLOW}ℹ  INFO${NC}: $1"; }

FAILURES=0

echo "========================================================"
echo "  Post-Deployment Validation — $ENVIRONMENT / $REGION"
echo "========================================================"

# ── 1. Get Terraform outputs ──────────────────────────────────────────────────
info "Reading Terraform outputs..."
cd "$TF_DIR"
ALB_DNS=$(terraform output -raw alb_dns_name 2>/dev/null || echo "")
ASG_NAME=$(terraform output -raw asg_name 2>/dev/null || echo "")
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
cd - > /dev/null

if [ -z "$ALB_DNS" ]; then
  fail "Could not read ALB DNS from Terraform outputs"
  exit 1
fi

# ── 2. Validate VPC ───────────────────────────────────────────────────────────
info "Checking VPC $VPC_ID..."
VPC_STATE=$(aws ec2 describe-vpcs --vpc-ids "$VPC_ID" \
  --region "$REGION" \
  --query 'Vpcs[0].State' --output text 2>/dev/null || echo "missing")

if [ "$VPC_STATE" = "available" ]; then
  pass "VPC $VPC_ID is available"
else
  fail "VPC $VPC_ID state: $VPC_STATE"
fi

# ── 3. Validate ASG ───────────────────────────────────────────────────────────
info "Checking ASG $ASG_NAME..."
ASG_DESIRED=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --region "$REGION" \
  --query 'AutoScalingGroups[0].DesiredCapacity' --output text)
ASG_HEALTHY=$(aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names "$ASG_NAME" \
  --region "$REGION" \
  --query 'length(AutoScalingGroups[0].Instances[?HealthStatus==`Healthy`])' --output text)

info "ASG desired=$ASG_DESIRED healthy=$ASG_HEALTHY"
if [ "$ASG_HEALTHY" -ge "$ASG_DESIRED" ] 2>/dev/null; then
  pass "ASG has $ASG_HEALTHY/$ASG_DESIRED healthy instances"
else
  fail "ASG healthy instance count ($ASG_HEALTHY) below desired ($ASG_DESIRED)"
fi

# ── 4. Validate ALB target group health ───────────────────────────────────────
info "Checking ALB target group health..."
HEALTHY_TARGETS=$(aws elbv2 describe-target-health \
  --target-group-arn "$(aws elbv2 describe-target-groups \
    --region "$REGION" \
    --query "TargetGroups[?contains(TargetGroupName,'$ENVIRONMENT')].TargetGroupArn | [0]" \
    --output text)" \
  --region "$REGION" \
  --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
  --output text 2>/dev/null || echo "0")

if [ "$HEALTHY_TARGETS" -gt "0" ] 2>/dev/null; then
  pass "ALB has $HEALTHY_TARGETS healthy targets"
else
  fail "No healthy targets in ALB target group"
fi

# ── 5. Validate /health endpoint ─────────────────────────────────────────────
info "Checking health endpoint at $ALB_DNS..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  --max-time 15 "http://$ALB_DNS/health" 2>/dev/null || echo "000")

if [ "$HTTP_STATUS" = "200" ]; then
  pass "Health endpoint returns HTTP 200"
elif [ "$HTTP_STATUS" = "301" ] || [ "$HTTP_STATUS" = "302" ]; then
  pass "Health endpoint redirects (HTTPS) — HTTP $HTTP_STATUS"
else
  fail "Health endpoint returned HTTP $HTTP_STATUS (expected 200 or 30x)"
fi

# ── 6. Validate CloudWatch log group ─────────────────────────────────────────
info "Checking CloudWatch log group..."
LOG_GROUP=$(MSYS_NO_PATHCONV=1 aws logs describe-log-groups \
  --log-group-name-prefix "/app/selfservice-ec2-$ENVIRONMENT" \
  --region "$REGION" \
  --query 'logGroups[0].logGroupName' --output text 2>/dev/null || echo "None")

if [ "$LOG_GROUP" != "None" ] && [ -n "$LOG_GROUP" ]; then
  pass "CloudWatch log group: $LOG_GROUP"
else
  fail "CloudWatch log group not found"
fi

# ── 7. Summary ────────────────────────────────────────────────────────────────
echo ""
echo "========================================================"
if [ "$FAILURES" -eq 0 ]; then
  echo -e "${GREEN}✅ ALL CHECKS PASSED — Environment is healthy${NC}"
else
  echo -e "${RED}❌ $FAILURES CHECK(S) FAILED — Review above errors${NC}"
fi
echo "========================================================"
echo ""
echo "ALB Endpoint: http://$ALB_DNS"
echo "ASG:          $ASG_NAME"

exit "$FAILURES"
