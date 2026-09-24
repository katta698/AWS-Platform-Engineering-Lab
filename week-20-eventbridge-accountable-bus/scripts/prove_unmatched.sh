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
  #
  # TWO THINGS THAT BOTH LOOK LIKE THEY SHOULD WORK AND DO NOT:
  #
  # 1. The CLI SHORTHAND form. `Detail={"orderId":"x"}` fails with
  #      Error parsing parameter '--entries': Expected: '=', received: '"'
  #    A shorthand value cannot contain a JSON object -- the brace ends the
  #    token. Most blog examples of put-events use shorthand, so this is the
  #    first wall anyone hits.
  #
  # 2. `--entries file://...` with a path from mktemp. The AWS CLI here is the
  #    Windows build, so a POSIX /tmp path is not a path it can open:
  #      Unable to load paramfile file:///tmp/tmp.XXXX: No such file or directory
  #
  # So: build real JSON and pass it inline. Note `Detail` is a JSON *string*,
  # not a nested object -- json.dumps twice, deliberately.
  local entries
  entries=$(python3 - "$1" "$2" "$SOURCE" "$BUS" <<'PY'
import json, sys
detail_type, order_id, source, bus = sys.argv[1:5]
print(json.dumps([{
    "Source": source,
    "DetailType": detail_type,
    "Detail": json.dumps({"orderId": order_id}),
    "EventBusName": bus,
}]))
PY
)
  aws_ events put-events --entries "$entries"     --query 'Entries[0].EventId' --output text 2>/dev/null
}

seen_in_log() {  # $1 log group, $2 needle, $3 window seconds -> count, or 0
  local start_ms
  start_ms=$(( ($(date +%s) - $3) * 1000 ))
  # --no-paginate is NOT optional here. The CLI auto-paginates
  # filter-log-events and applies --query PER PAGE, so `length(events)` comes
  # back as one number per page, joined by a newline, which bash then fails
  # to compare as an integer: "syntax error: invalid arithmetic operator".
  # The visible symptom was a BROKEN check announcing that delivery was broken,
  # at a moment when the consumer had in fact been invoked four times. The
  # measurement was wrong, not the system. Filtering on a unique event id means
  # one page is always enough.
  aws_ logs filter-log-events --log-group-name "$1" --start-time "$start_ms"     --filter-pattern "\"$2\"" --no-paginate --query 'length(events)'     --output text 2>/dev/null | head -1
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
# 3. TWO FAILURE MODES, AND THE QUEUE EVERYONE CONFIGURES CATCHES ONLY ONE
#
# The DLQ attached to an EventBridge target catches DELIVERY failures -- "I
# could not hand this over": NO_PERMISSIONS, NO_RESOURCE, THROTTLING.
#
# It does NOT catch the target accepting an event and then failing. EventBridge
# invokes a Lambda target asynchronously, so its delivery succeeded the moment
# Lambda said yes. The function raising afterwards is Lambda's business, and it
# needs Lambda's own on-failure destination -- a different mechanism, in a
# different place, that most walkthroughs never mention.
#
# This section publishes a poison event and checks BOTH queues, because the
# interesting result is which one fills.
# ---------------------------------------------------------------------------
POISON_DETAIL_TYPE="${POISON_DETAIL_TYPE:-order.poison}"
echo
echo "3. A target that accepts the event and then fails"

depth() {  # $1 queue url -> visible message count
  # ApproximateNumberOfMessagesVisible is NOT a valid attribute name; the API
  # rejects it with InvalidAttributeName. The correct one is
  # ApproximateNumberOfMessages. An earlier version of this script asked for the
  # wrong name, got an error on stderr, defaulted both readings to 0, and
  # reported "depth unchanged" -- a conclusion drawn from two failed reads.
  aws_ sqs get-queue-attributes --queue-url "$1" --attribute-names All     --query 'Attributes.ApproximateNumberOfMessages' --output text 2>/dev/null
}

EB_DLQ=$(aws_ sqs get-queue-url --queue-name "${BUS}-dlq" --query QueueUrl --output text 2>/dev/null)
FN_DLQ=$(aws_ sqs get-queue-url --queue-name "${BUS}-function-failures" --query QueueUrl --output text 2>/dev/null)

if [[ -z "$EB_DLQ" || "$EB_DLQ" == "None" || -z "$FN_DLQ" || "$FN_DLQ" == "None" ]]; then
  broke "could not resolve both queues -- nothing was tested"
else
  eb_before=$(depth "$EB_DLQ"); fn_before=$(depth "$FN_DLQ")
  if [[ -z "$eb_before" || -z "$fn_before" ]]; then
    broke "could not read queue depth -- nothing was tested"
  else
    poison_id=$(publish "$POISON_DETAIL_TYPE" "poison-$(date +%s)")
    if [[ -z "$poison_id" || "$poison_id" == "None" ]]; then
      broke "PutEvents returned no event id -- nothing was tested"
    else
      ok "published a poison event, EventId ${poison_id:0:8}"
      echo "     EventBridge DLQ before: ${eb_before}   function-failures before: ${fn_before}"
      echo "     waiting ${SETTLE}s..."
      sleep "$SETTLE"

      # PROVE THE FUNCTION ACTUALLY RAN AND FAILED, from its own log.
      #
      # The first version of this read the Lambda Errors METRIC over a sliding
      # 15-minute window and compared before/after. That is not a measurement,
      # it is a moving target: the reading went 1.0 -> 0.0 simply because an
      # older error aged out of the window, and the check concluded the poison
      # event had never arrived. It had.
      #
      # The handler logs "poison event_id=<id> -- failing deliberately" on the
      # line before it raises, so one grep for this event id answers both
      # questions exactly: did it arrive, and did it fail. Same evidence the
      # other two checks use.
      n=$(seen_in_log "$CONSUMER_LOG" "$poison_id" 300)
      if [[ "${n:-0}" -eq 0 ]]; then
        broke "the consumer log has no trace of ${poison_id:0:8}; it never arrived, so neither queue result means anything"
      else
        ok "the consumer received it and raised -- the failure is real"

        eb_after=$(depth "$EB_DLQ"); fn_after=$(depth "$FN_DLQ")

        if [[ "${eb_after:-0}" -eq "${eb_before:-0}" ]]; then
          ok "EventBridge DLQ still ${eb_after} -- it saw no DELIVERY failure, because there was none"
        else
          bad "EventBridge DLQ grew ${eb_before} -> ${eb_after}; that contradicts the post's claim about what it catches"
        fi

        if [[ "${fn_after:-0}" -gt "${fn_before:-0}" ]]; then
          ok "Lambda on-failure destination ${fn_before} -> ${fn_after} -- THIS is what catches a target that fails"
          echo "         Two failure modes, two mechanisms. The queue every tutorial"
          echo "         shows you to configure catches only the other one."
        else
          bad "neither queue captured it (${fn_before} -> ${fn_after}); the failure went nowhere at all"
        fi
      fi
    fi
  fi
fi

echo
echo "----------------------------------------------------------------"
printf 'passed %d   failed %d   BROKEN %d
' "$pass" "$fail" "$broken"

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
