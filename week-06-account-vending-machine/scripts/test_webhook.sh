#!/bin/bash
set -euo pipefail

# Usage: bash test_webhook.sh <api_gateway_url> <webhook_secret> [ticket_id] <account_email> [target_ou]
#
# account_email is REQUIRED and has no default: a vended account is a real AWS
# account tied to a real mailbox, so the address has to be a deliberate choice
# rather than whatever was left in the script.
# api_gateway_url: from terraform output api_gateway_url (HCP UI -> Outputs)
# webhook_secret:  the value you set as the webhook_secret HCP workspace variable

API_URL="${1:?Usage: $0 <api_gateway_url> <webhook_secret> [ticket_id] [account_email] [target_ou]}"
SECRET="${2:?Usage: $0 <api_gateway_url> <webhook_secret> [ticket_id] [account_email] [target_ou]}"
TICKET_ID="${3:-RITM0010001}"
ACCOUNT_EMAIL="${4:?Usage: $0 <api_gateway_url> <webhook_secret> [ticket_id] <account_email> [target_ou]}"
TARGET_OU="${5:-Sandbox}"

BODY=$(cat <<EOF
{"ticket_id":"${TICKET_ID}","requested_by":"jay","account_name":"sandbox-test-01","account_email":"${ACCOUNT_EMAIL}","target_ou":"${TARGET_OU}"}
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
echo "=== Done — check Step Functions console for the avm-${TICKET_ID} execution ==="
