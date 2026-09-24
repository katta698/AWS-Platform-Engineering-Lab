#!/usr/bin/env bash
# What happens to an event that no rule matches?
#
# The advertised answer is "it is discarded". The interesting part is how
# thoroughly indistinguishable that is from success: PutEvents returns HTTP 200
# and an event id, the publisher's code carries on, and nothing anywhere says a
# decision was made to drop it.
#
# THE RULE THIS SCRIPT IS BUILT AROUND, carried from two prior weeks.
#
# Week 18's isolation test reported two passes out of four against pods that
# never started -- the checks grepped for "denied" and work that never happens
# produces no string. Week 19's drift test twice reported BROKEN because Argo CD
# reverted a change faster than the test could observe it; the fix both times
# was to measure a fact that cannot be undone rather than a state that can.
#
# So: every check here proves its own precondition. If the event was never
# published, that is a HARD FAILURE, never a pass. A test that cannot tell
# "discarded" from "never sent" is not a test.
set -uo pipefail

BUS="${BUS:-week20-bus}"
SOURCE="${EVENT_SOURCE:-platform.orders}"
HANDLED="${HANDLED_DETAIL_TYPE:-order.created}"
TYPO="${TYPO_DETAIL_TYPE:-order.crated}"   # one transposed letter. That is all it takes.
CONSUMER_LOG="${CONSUMER_LOG:-/aws/lambda/${BUS}-consumer}"
CATCHALL_LOG="${CATCHALL_LOG:-/aws/events/${BUS}-catch-all}"
PROFILE="${AWS_PROFILE:-personal}"
SETTLE="${SETTLE:-45}"

pass=0; fail=0; broken=0
ok()    { printf '  [ok]     %s\n' "$1"; pass=$((pass+1)); }
bad()   { printf '  [FAIL]   %s\n' "$1"; fail=$((fail+1)); }
# A check that could not run is its own category. Folding it into "pass" is how
# Week 18 shipped a green test that proved nothing.
broke() { printf '  [BROKEN] %s\n' "$1"; broken=$((broken+1)); }

aws_() { MSYS_NO_PATHCONV=1 aws --profile "$PROFILE" "$@"; }

publish() {  # $1 detail-type, $2 order id -> echoes the event id, empty on failure
  aws_ events put-events --entries \
    "Source=${SOURCE},DetailType=$1,Detail={\"orderId\":\"$2\"},EventBusName=${BUS}" \
    --query 'Entries[0].EventId' --output text 2>/dev/null
}

seen_in_log() {  # $1 log group, $2 needle, $3 window seconds
  local start_ms
  start_ms=$(( ($(date +%s) - $3) * 1000 ))
  aws_ logs filter-log-events --log-group-name "$1" --start-time "$start_ms" \
    --filter-pattern "\"$2\"" --query 'length(events)' --output text 2>/dev/null
}

echo "Preconditions"
if ! aws_ events describe-event-bus --name "$BUS" >/dev/null 2>&1; then
  echo "  bus $BUS not found -- is the stack applied?"; exit 2
fi
ok "bus $BUS exists"

for lg in "$CONSUMER_LOG" "$CATCHALL_LOG"; do
  if ! aws_ logs describe-log-groups --log-group-name-prefix "$lg" \
       --query 'logGroups[0].logGroupName' --output text 2>/dev/null | grep -q .; then
    echo "  log group $lg missing"; exit 2
  fi
done
ok "both log groups exist"

# ---------------------------------------------------------------------------
# 1. THE HAPPY PATH -- establishes that delivery works at all.
#
# Without this the whole script is worthless: "nothing arrived" is only
# meaningful once "something can arrive" has been shown on the same run.
# ---------------------------------------------------------------------------
echo
echo "1. An event the rule matches"

good_id=$(publish "$HANDLED" "matched-$(date +%s)")
if [[ -z "$good_id" || "$good_id" == "None" ]]; then
  broke "PutEvents returned no event id -- nothing was tested"
else
  ok "published, EventId ${good_id:0:8}"
  echo "     waiting ${SETTLE}s for delivery..."
  sleep "$SETTLE"
  n=$(seen_in_log "$CONSUMER_LOG" "$good_id" 300)
  if [[ "${n:-0}" -gt 0 ]]; then
    ok "consumer received it -- delivery works"
  else
    broke "consumer never saw a MATCHED event; delivery itself is broken, so the unmatched result below would mean nothing"
  fi
fi

# ---------------------------------------------------------------------------
# 2. THE EVENT THAT MATCHED NOTHING
#
# One transposed letter in the detail-type. No error at publish, no error at
# deploy -- an event pattern is a filter, and a filter that matches nothing is
# not a failure condition.
# ---------------------------------------------------------------------------
echo
echo "2. An event NO rule matches (detail-type '$TYPO' vs '$HANDLED')"

bad_id=$(publish "$TYPO" "unmatched-$(date +%s)")
if [[ -z "$bad_id" || "$bad_id" == "None" ]]; then
  broke "PutEvents returned no event id -- nothing was tested"
else
  # THIS is the finding, and it is worth stating as a pass rather than burying:
  # the API call succeeded exactly as it does for a good event.
  ok "PutEvents returned HTTP 200 and EventId ${bad_id:0:8} -- indistinguishable from success"
  echo "     waiting ${SETTLE}s to see whether anything consumes it..."
  sleep "$SETTLE"

  n=$(seen_in_log "$CONSUMER_LOG" "$bad_id" 300)
  if [[ "${n:-0}" -eq 0 ]]; then
    ok "nothing consumed it -- the consumer never saw it"
  else
    bad "the consumer DID receive it; the rule pattern is broader than the post claims"
  fi

  # ---- and now the detection, which is the part you have to build ----
  n=$(seen_in_log "$CATCHALL_LOG" "$bad_id" 300)
  if [[ "${n:-0}" -gt 0 ]]; then
    ok "the catch-all rule recorded it -- this is the ONLY reason it is visible"
    echo "         EventBridge publishes MatchedEvents per RULE. There is no"
    echo "         metric for 'matched no rule at all'. You buy that visibility"
    echo "         with a second delivery, and you pay for it."
  else
    bad "the catch-all did not record it -- detection is not working, so an unmatched event here would be genuinely invisible"
  fi
fi

# ---------------------------------------------------------------------------
# 3. A REAL FAILED DELIVERY -> DLQ
#
# Pushed through the bus, not injected into the queue. A DLQ that has only ever
# held a hand-written message has not been tested.
# ---------------------------------------------------------------------------
echo
echo "3. A delivery that fails (consumer raises on '$POISON_DETAIL_TYPE')"
POISON_DETAIL_TYPE="${POISON_DETAIL_TYPE:-order.poison}"
DLQ_URL="${DLQ_URL:-}"

if [[ -z "$DLQ_URL" ]]; then
  DLQ_URL=$(aws_ sqs get-queue-url --queue-name "${BUS}-dlq" --query QueueUrl --output text 2>/dev/null)
fi

if [[ -z "$DLQ_URL" || "$DLQ_URL" == "None" ]]; then
  broke "could not resolve the DLQ url -- nothing was tested"
else
  before=$(aws_ sqs get-queue-attributes --queue-url "$DLQ_URL" \
    --attribute-names ApproximateNumberOfMessagesVisible \
    --query 'Attributes.ApproximateNumberOfMessagesVisible' --output text 2>/dev/null)
  poison_id=$(publish "$POISON_DETAIL_TYPE" "poison-$(date +%s)")

  if [[ -z "$poison_id" || "$poison_id" == "None" ]]; then
    broke "PutEvents returned no event id -- nothing was tested"
  else
    ok "published a poison event, EventId ${poison_id:0:8} (queue depth before: ${before:-0})"
    echo "     waiting ${SETTLE}s for the retry policy to exhaust..."
    sleep "$SETTLE"
    after=$(aws_ sqs get-queue-attributes --queue-url "$DLQ_URL" \
      --attribute-names ApproximateNumberOfMessagesVisible \
      --query 'Attributes.ApproximateNumberOfMessagesVisible' --output text 2>/dev/null)
    if [[ "${after:-0}" -gt "${before:-0}" ]]; then
      ok "DLQ depth ${before:-0} -> ${after:-0} -- a real failed delivery was captured"
    else
      bad "DLQ depth unchanged (${before:-0} -> ${after:-0}); the failure went somewhere else, or nowhere"
    fi
  fi
fi

echo
echo "----------------------------------------------------------------"
printf 'passed %d   failed %d   BROKEN %d\n' "$pass" "$fail" "$broken"

if (( broken > 0 )); then
  echo
  echo "BROKEN checks did not run. They are not passes and not failures --"
  echo "they are silence, and silence is what Week 18 published as success."
  echo "Fix the precondition and run again before reporting anything."
  exit 3
fi
if (( fail > 0 )); then
  echo "Some behaviour did not match what the post intends to claim."
  exit 1
fi
echo "All checks ran and behaved as described."
