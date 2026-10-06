#!/usr/bin/env bash
# Run the six tests in order and print a pass/fail line for each.
#
#   bash scripts/test_gate.sh <stamp-from-push_images>
#
# Order matters. Test 1 establishes that the happy path works; a failure in
# test 2 means nothing if test 1 never passed. Nothing here is interactive and
# nothing is left running.

set -uo pipefail

cd "$(dirname "$0")/.."

STAMP="${1:-}"
if [ -z "$STAMP" ]; then
  echo "usage: bash scripts/test_gate.sh <stamp>   (printed by push_images.sh)" >&2
  exit 2
fi

REGION="${AWS_REGION:-us-east-1}"
cd terraform/environments/dev
REPO=$(terraform output -raw app_repository_name)
OUTSIDE=$(terraform output -raw outside_filter_repository_name)
cd ../../..

PASS=0; FAIL=0
result() { # result <ok|no> <text>
  if [ "$1" = "ok" ]; then PASS=$((PASS+1)); echo "  [ok]   $2"; else FAIL=$((FAIL+1)); echo "  [FAIL] $2"; fi
}

digest_for() { # digest_for <repo> <tag>
  aws ecr describe-images --repository-name "$1" --region "$REGION" \
    --image-ids imageTag="$2" --query 'imageDetails[0].imageDigest' --output text 2>/dev/null
}

tags_for() { # tags_for <repo> <digest>
  aws ecr describe-images --repository-name "$1" --region "$REGION" \
    --image-ids imageDigest="$2" --query 'imageDetails[0].imageTags' --output text 2>/dev/null
}

signing_status() { # signing_status <repo> <digest>
  aws ecr describe-image-signing-status --repository-name "$1" --region "$REGION" \
    --image-id imageDigest="$2" --output json 2>&1
}

echo
echo "Week 22 -- image gate tests"
echo "repository: $REPO"
echo "control:    $OUTSIDE"
echo

# ---------------------------------------------------------------------------
echo "1. A clean image is signed and passes the gate"
CLEAN_D=$(digest_for "$REPO" "clean-${STAMP}")
if [ -z "$CLEAN_D" ] || [ "$CLEAN_D" = "None" ]; then
  result no "clean image not found -- did push_images.sh run?"
else
  SIG=$(signing_status "$REPO" "$CLEAN_D")
  echo "$SIG" | grep -qi "signed\|SUCCESS" && result ok "signed" || result no "not signed: $(echo "$SIG" | head -2 | tr -d '\n')"
  sleep 5
  STILL=$(tags_for "$REPO" "$CLEAN_D")
  case "$STILL" in
    *clean-${STAMP}*) result ok "still carries its deployable tag (not quarantined)" ;;
    *)                result no "clean image lost its tag -- gate quarantined a clean image: '$STILL'" ;;
  esac
fi
echo

# ---------------------------------------------------------------------------
echo "2. An OS-vulnerable image is quarantined"
OS_D=$(digest_for "$REPO" "vuln-os-${STAMP}")
if [ -z "$OS_D" ] || [ "$OS_D" = "None" ]; then
  OS_D=$(aws ecr describe-images --repository-name "$REPO" --region "$REGION" \
          --query "imageDetails[?contains(to_string(imageTags), 'vuln-os')]|[0].imageDigest" --output text 2>/dev/null)
fi
if [ -z "$OS_D" ] || [ "$OS_D" = "None" ]; then
  result no "vuln-os image not found at all"
else
  T=$(tags_for "$REPO" "$OS_D")
  case "$T" in
    *quarantined*) result ok "quarantined, tags now: $T" ;;
    *)             result no "still deployable, tags: $T (scan may not have finished -- rerun)" ;;
  esac
fi
echo

# ---------------------------------------------------------------------------
echo "3. A SIGNED image with a vulnerable library is still quarantined"
echo "   (signing proves who pushed it, not that it is safe)"
LIB_D=$(digest_for "$REPO" "vuln-lib-${STAMP}")
if [ -z "$LIB_D" ] || [ "$LIB_D" = "None" ]; then
  LIB_D=$(aws ecr describe-images --repository-name "$REPO" --region "$REGION" \
           --query "imageDetails[?contains(to_string(imageTags), 'vuln-lib')]|[0].imageDigest" --output text 2>/dev/null)
fi
if [ -z "$LIB_D" ] || [ "$LIB_D" = "None" ]; then
  result no "vuln-lib image not found"
else
  SIG=$(signing_status "$REPO" "$LIB_D")
  echo "$SIG" | grep -qi "signed\|SUCCESS" && result ok "signature is valid" || result no "not signed, so the test proves nothing"
  T=$(tags_for "$REPO" "$LIB_D")
  case "$T" in
    *quarantined*) result ok "quarantined despite a valid signature" ;;
    *)             result no "signed and still deployable, tags: $T" ;;
  esac
  echo "   language-package findings (what basic scanning cannot see):"
  aws inspector2 list-findings --region "$REGION" \
    --filter-criteria "{\"ecrImageHash\":[{\"comparison\":\"EQUALS\",\"value\":\"$LIB_D\"}]}" \
    --query 'findings[].{sev:severity,pkg:packageVulnerabilityDetails.vulnerablePackages[0].packageManager,id:packageVulnerabilityDetails.vulnerabilityId}' \
    --output text 2>/dev/null | grep -iE 'pip|npm|maven' | head -5 | sed 's/^/     /' || echo "     (none reported yet)"
fi
echo

# ---------------------------------------------------------------------------
echo "4. A repository outside the filter is neither signed nor scanned"
echo "   (proves the filter is a real boundary, not decoration)"
OUT_D=$(aws ecr describe-images --repository-name "$OUTSIDE" --region "$REGION" \
         --query 'imageDetails[0].imageDigest' --output text 2>/dev/null)
if [ -z "$OUT_D" ] || [ "$OUT_D" = "None" ]; then
  result no "nothing pushed to the control repository -- see README step 7d"
else
  SIG=$(signing_status "$OUTSIDE" "$OUT_D")
  if echo "$SIG" | grep -qi "signed\|SUCCESS"; then
    result no "image OUTSIDE the filter got signed -- the filter is not holding"
  else
    result ok "not signed, as intended"
  fi
fi
echo

# ---------------------------------------------------------------------------
echo "5. How long is the window between push and enforcement?"
echo "   (an unscanned image is pullable during it -- this measures the risk)"
PUSHED=$(aws ecr describe-images --repository-name "$REPO" --region "$REGION" \
          --image-ids imageDigest="${OS_D:-none}" \
          --query 'imageDetails[0].imagePushedAt' --output text 2>/dev/null)
if [ -n "$PUSHED" ] && [ "$PUSHED" != "None" ]; then
  echo "   pushed at:     $PUSHED"
  echo "   quarantined at: see the gate log --"
  aws logs filter-log-events --region "$REGION" \
    --log-group-name "$(cd terraform/environments/dev && terraform output -raw gate_log_group)" \
    --filter-pattern "QUARANTINE" --max-items 5 \
    --query 'events[].message' --output text 2>/dev/null | head -5 | sed 's/^/     /'
  result ok "window recorded above -- put both timestamps in the post"
else
  result no "could not read the push timestamp"
fi
echo

# ---------------------------------------------------------------------------
echo "6. The gate fails CLOSED, not open"
echo "   (a security control that waves images through when broken is worse"
echo "    than none, because the dashboard stays green)"
GATE=$(cd terraform/environments/dev && terraform output -raw gate_function_name)
RESP=$(aws lambda invoke --region "$REGION" --function-name "$GATE" \
        --payload '{"detail":{"scan-status":"INITIAL_SCAN_COMPLETE"}}' \
        --cli-binary-format raw-in-base64-out /dev/stdout 2>/dev/null)
if echo "$RESP" | grep -qi "errorMessage\|Undetermined"; then
  result ok "a malformed event raises instead of returning allow"
else
  result no "a malformed event did NOT fail -- the gate may fail open: $RESP"
fi
echo

echo "-----------------------------------------"
echo "  $PASS passed, $FAIL failed"
echo "-----------------------------------------"
[ "$FAIL" -eq 0 ] || exit 1
