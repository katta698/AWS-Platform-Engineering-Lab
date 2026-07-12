#!/bin/bash
set -euo pipefail

# Usage: bash test_webhook.sh <api_gateway_url> <webhook_secret> [ticket_id] [service_name] [image_uri]
# api_gateway_url: from terraform output api_gateway_url (HCP UI -> Outputs)
# webhook_secret:  the value you set as the webhook_secret HCP workspace variable
#
# No ticket_sys_id is sent - there's no real ServiceNow ticket behind a
# manual test, and status_notifier skips the ServiceNow update gracefully
# when it's absent (confirmed working during live testing, 2026-07-12).
#
# image_uri MUST be an image already in PRIVATE ECR, not a public registry
# tag like public.ecr.aws/... - this VPC has no NAT Gateway and no route to
# AWS's Public ECR Gallery (only private ECR, via VPC endpoints). Push one
# first if you don't have one yet:
#   aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <account_id>.dkr.ecr.us-east-1.amazonaws.com
#   docker pull nginx:latest && docker tag nginx:latest <account_id>.dkr.ecr.us-east-1.amazonaws.com/fargate-selfservice-<service_name>:latest
#   docker push <account_id>.dkr.ecr.us-east-1.amazonaws.com/fargate-selfservice-<service_name>:latest
# (the ECR repo itself is created automatically by the first ticket for that
# service_name, so push after the repo exists, or create it once yourself.)

API_URL="${1:?Usage: $0 <api_gateway_url> <webhook_secret> [ticket_id] [service_name] [image_uri]}"
SECRET="${2:?Usage: $0 <api_gateway_url> <webhook_secret> [ticket_id] [service_name] [image_uri]}"
TICKET_ID="${3:-RITM0020001}"
SERVICE_NAME="${4:-demo-nginx}"
IMAGE_URI="${5:?image_uri is required - must be a private ECR image, see comments above}"

BODY=$(cat <<EOF
{"ticket_id":"${TICKET_ID}","service_name":"${SERVICE_NAME}","image_uri":"${IMAGE_URI}","container_port":80,"cpu":256,"memory":512,"desired_count":1}
EOF
)

SIGNATURE="sha256=$(printf '%s' "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | sed 's/^.* //')"

echo "=== Sending test webhook ==="
echo "URL: $API_URL"
echo "Body: $BODY"
echo "Signature: $SIGNATURE"
echo ""

curl -i -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "x-servicenow-hmac: $SIGNATURE" \
  -d "$BODY"

echo ""
echo "=== Done — check Step Functions console for the fargate-${TICKET_ID} execution ==="
echo "=== Once it succeeds, the service is reachable at http://<alb_dns_name>/${SERVICE_NAME}/ ==="
