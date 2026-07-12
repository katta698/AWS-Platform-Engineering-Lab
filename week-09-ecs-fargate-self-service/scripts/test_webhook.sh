#!/bin/bash
set -euo pipefail

# Usage: bash test_webhook.sh <api_gateway_url> <webhook_secret>
# api_gateway_url: from terraform output api_gateway_url (HCP UI -> Outputs)
# webhook_secret:  the value you set as the webhook_secret HCP workspace variable
#
# Deploys a public demo image (nginx) — self-service tickets point at any
# existing image URI; this pipeline provisions the service, it doesn't build
# or push images (that's a CI/CD concern, out of scope this week).

API_URL="${1:?Usage: $0 <api_gateway_url> <webhook_secret> [ticket_id] [service_name]}"
SECRET="${2:?Usage: $0 <api_gateway_url> <webhook_secret> [ticket_id] [service_name]}"
TICKET_ID="${3:-RITM0020001}"
SERVICE_NAME="${4:-demo-nginx}"

BODY=$(cat <<EOF
{"ticket_id":"${TICKET_ID}","service_name":"${SERVICE_NAME}","image_uri":"public.ecr.aws/nginx/nginx:latest","container_port":80,"cpu":256,"memory":512,"desired_count":1}
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
