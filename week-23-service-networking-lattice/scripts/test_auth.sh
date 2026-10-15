#!/usr/bin/env bash
# Run the six authorisation tests in order and print pass/fail for each.
#
#   bash scripts/test_auth.sh
#
# Order matters. Test 2 establishes that an allowed call works at all; a
# refusal in test 3 means nothing until test 2 has passed, because every call
# would be refused if the plumbing were simply broken.
#
# Nothing here is interactive and nothing is left running.

set -uo pipefail

cd "$(dirname "$0")/.."

REGION="${AWS_REGION:-us-east-1}"
TF=terraform/environments/dev

# Values are discovered from AWS by name prefix rather than read from
# terraform output. The outputs are the obvious source, but they need HCP
# reachable on every run -- a TLS timeout to app.terraform.io stopped these
# tests once already, which is a silly reason to be unable to test live
# infrastructure that is sitting right there.
PREFIX="${NAME_PREFIX:-week23-lattice}"

FN=$(aws lambda list-functions --region "$REGION"       --query "Functions[?FunctionName=='${PREFIX}-client'].FunctionName" --output text 2>/dev/null)
SERVICE_ARN=$(aws vpc-lattice list-services --region "$REGION"       --query "items[?name=='${PREFIX}-rates'].arn" --output text 2>/dev/null)
STRANGER=$(aws iam get-role --role-name "${PREFIX}-stranger"       --query 'Role.Arn' --output text 2>/dev/null)

# Falls back to the outputs if the names ever change.
out() { (cd "$TF" && terraform output -raw "$1" 2>/dev/null); }
[ -z "$FN" ]          && FN=$(out client_function_name)
[ -z "$SERVICE_ARN" ] && SERVICE_ARN=$(out service_arn)
[ -z "$STRANGER" ]    && STRANGER=$(out stranger_role_arn)

if [ -z "$FN" ] || [ -z "$SERVICE_ARN" ]; then
  echo "Could not find the deployed resources. Has the apply run?" >&2
  exit 2
fi

AUTH_NOW=$(aws vpc-lattice get-service --region "$REGION"       --service-identifier "$SERVICE_ARN" --query 'authType' --output text 2>/dev/null)

PASS=0; FAIL=0
result() {
  if [ "$1" = "ok" ]; then PASS=$((PASS+1)); echo "  [ok]   $2"
  else FAIL=$((FAIL+1)); echo "  [FAIL] $2"; fi
}

# call <json-payload> -> echoes the HTTP status the service returned
call() {
  aws lambda invoke --region "$REGION" --function-name "$FN" \
    --cli-binary-format raw-in-base64-out --payload "$1" \
    /tmp/wk23_out.json >/dev/null 2>&1
  python -c "
import json
try:
    d=json.load(open('/tmp/wk23_out.json'))
    print(d.get('status') if d.get('status') is not None else 'ERR:'+str(d.get('error'))[:60])
except Exception as e:
    print('UNREADABLE')
" 2>/dev/null
}

echo
echo "Week 23 -- VPC Lattice authorisation tests"
echo "service: $SERVICE_ARN"
echo "auth type on the service: $AUTH_NOW"
echo

# ---------------------------------------------------------------------------
echo "1. An unsigned request is refused"
S=$(call '{"mode":"unsigned","method":"GET","path":"/rates"}')
[ "$S" = "403" ] && result ok "403, as it should be" \
                 || result no "expected 403, got $S"
echo

echo "2. A signed request from the named role succeeds"
echo "   (nothing below means anything until this passes)"
S=$(call '{"mode":"signed","method":"GET","path":"/rates"}')
[ "$S" = "200" ] && result ok "200 from the allowed identity" \
                 || result no "expected 200, got $S -- the plumbing is broken, not the policy"
echo

echo "3. The SAME function, signed as a different role, is refused"
echo "   Same VPC, same subnet, same security group. Only the identity differs."
S=$(call "{\"mode\":\"signed\",\"role_arn\":\"$STRANGER\",\"method\":\"GET\",\"path\":\"/rates\"}")
[ "$S" = "403" ] && result ok "403 -- identity is what was checked, not network position" \
                 || result no "expected 403, got $S"
echo

echo "4. The allowed role using a method the policy does not permit"
S=$(call '{"mode":"signed","method":"POST","path":"/rates","body":"{}"}')
[ "$S" = "403" ] && result ok "403 -- the condition key is enforced, not decorative" \
                 || result no "expected 403, got $S"
echo

# ---------------------------------------------------------------------------
echo "5. THE TRAP: a restrictive policy on a service whose auth type is NONE"
echo "   Flip the variable, apply, and the policy is still attached."
AUTH="$AUTH_NOW"
if [ "$AUTH" = "NONE" ]; then
  S=$(call "{\"mode\":\"signed\",\"role_arn\":\"$STRANGER\",\"method\":\"POST\",\"path\":\"/rates\"}")
  [ "$S" = "200" ] && result ok "200 -- the wrong role, the wrong method, allowed anyway" \
                   || result no "expected 200 (policy inert), got $S"
  STATE=$(aws vpc-lattice get-auth-policy --region "$REGION" \
            --resource-identifier "$SERVICE_ARN" --query 'state' --output text 2>/dev/null)
  [ "$STATE" = "Inactive" ] && result ok "and the policy reports state=Inactive" \
                            || result no "expected state Inactive, got '$STATE'"
else
  echo "  [skip] run again with service_auth_type=NONE to see this one"
  echo "         terraform apply -var service_auth_type=NONE"
fi
echo

# ---------------------------------------------------------------------------
echo "6. Auth type AWS_IAM with the policy removed fails CLOSED"
if [ "$AUTH" = "AWS_IAM" ]; then
  echo "  (destructive to the policy; run deliberately)"
  echo "  aws vpc-lattice delete-auth-policy --resource-identifier $SERVICE_ARN"
  echo "  then re-run test 2 and expect 403, then terraform apply to restore"
  echo "  [skip] not run automatically -- it edits live state outside Terraform"
else
  echo "  [skip] needs auth type AWS_IAM"
fi
echo

echo "-----------------------------------------"
echo "  $PASS passed, $FAIL failed"
echo "-----------------------------------------"
[ "$FAIL" -eq 0 ] || exit 1
