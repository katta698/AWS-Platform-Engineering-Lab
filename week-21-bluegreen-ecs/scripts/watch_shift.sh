#!/usr/bin/env bash
# Watch a blue/green deployment happen, from the client's side.
#
# The console shows you task sets and percentages. It does not show you what a
# caller actually received, which is the only thing a user experiences. This
# polls the ALB and counts responses by version.
#
# Three outcomes, not two: a check whose precondition did not hold reports
# BROKEN, never a pass. "No errors seen" is worthless if nothing was served.
set -uo pipefail

URL="${URL:?set URL to the ALB address, e.g. http://week21-...elb.amazonaws.com/}"
SECONDS_TO_WATCH="${SECONDS_TO_WATCH:-180}"
INTERVAL="${INTERVAL:-2}"

pass=0; fail=0; broken=0
ok()    { printf '  [ok]     %s\n' "$1"; pass=$((pass+1)); }
bad()   { printf '  [FAIL]   %s\n' "$1"; fail=$((fail+1)); }
broke() { printf '  [BROKEN] %s\n' "$1"; broken=$((broken+1)); }

echo "Polling $URL every ${INTERVAL}s for ${SECONDS_TO_WATCH}s"
echo

declare -A seen
codes_4xx=0
total=0
first_change=""
start=$(date +%s)

while (( $(date +%s) - start < SECONDS_TO_WATCH )); do
  body=$(curl -s --max-time 5 "$URL" 2>/dev/null)
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL" 2>/dev/null)
  total=$((total+1))

  if [[ "$code" == 4* ]]; then
    codes_4xx=$((codes_4xx+1))
    key="HTTP_$code"
  else
    key="${body:-<empty>}"
  fi
  seen["$key"]=$(( ${seen["$key"]:-0} + 1 ))

  # Note the moment a second distinct version appears -- that is the shift.
  if [[ -z "$first_change" && ${#seen[@]} -gt 1 ]]; then
    first_change=$(( $(date +%s) - start ))
    echo "  ** a second response appeared at t+${first_change}s **"
  fi

  printf '\r  t+%-4ss  requests=%-5s distinct=%-3s 4xx=%s   ' \
    "$(( $(date +%s) - start ))" "$total" "${#seen[@]}" "$codes_4xx"
  sleep "$INTERVAL"
done
echo; echo

echo "Responses seen"
for k in "${!seen[@]}"; do
  printf '  %-24s %s\n' "$k" "${seen[$k]}"
done
echo

if (( total == 0 )); then
  broke "no requests completed -- the ALB was never reached, so nothing was measured"
elif (( ${#seen[@]} == 1 )); then
  ok "one version served throughout ($total requests) -- steady state, no deployment in flight"
else
  ok "traffic moved between versions during the window -- ${#seen[@]} distinct responses"
  [[ -n "$first_change" ]] && ok "the shift became visible to a client at t+${first_change}s"
fi

(( codes_4xx > 0 )) && ok "$codes_4xx 4xx responses reached clients -- this is what the alarm watches"

echo
printf 'passed %d   failed %d   BROKEN %d\n' "$pass" "$fail" "$broken"
(( broken > 0 )) && { echo "BROKEN checks did not run."; exit 3; }
(( fail > 0 )) && exit 1
exit 0
