#!/usr/bin/env bash
# Does a replay re-deliver to the rules that existed when the event was
# archived, or to the rules that exist now?
#
# It matters because people reach for replay during an incident: "we lost an
# hour of events, replay them." If replay followed the ORIGINAL routing, that
# is a time machine. If it follows CURRENT routing, it is something else --
# closer to re-publishing old events into today's system, with today's
# consequences.
#
# THE DEMONSTRATION
#
# 1. Publish an event with the typo detail-type. No rule matches it. It is
#    archived anyway, because the archive sits in front of the rules.
# 2. THEN add a rule that does match it.
# 3. Replay the window.
#
# If the event arrives at the consumer, replay used the rule that did not exist
# when the event was published -- and an event that was delivered to nobody has
# now been delivered to somebody.
#
# Same discipline as prove_unmatched.sh: a check whose precondition did not hold
# reports BROKEN, never a pass.
set -uo pipefail

BUS="${BUS:-week20-bus}"
ARCHIVE="${ARCHIVE:-${BUS}-archive}"
SOURCE="${EVENT_SOURCE:-platform.orders}"
TYPO="${TYPO_DETAIL_TYPE:-order.crated}"
CONSUMER_LOG="${CONSUMER_LOG:-/aws/lambda/${BUS}-consumer}"
TEMP_RULE="${BUS}-replay-probe"
PROFILE="${AWS_PROFILE:-personal}"
SETTLE="${SETTLE:-60}"

pass=0; fail=0; broken=0
ok()    { printf '  [ok]     %s\n' "$1"; pass=$((pass+1)); }
bad()   { printf '  [FAIL]   %s\n' "$1"; fail=$((fail+1)); }
broke() { printf '  [BROKEN] %s\n' "$1"; broken=$((broken+1)); }
aws_()  { MSYS_NO_PATHCONV=1 aws --profile "$PROFILE" "$@"; }

cleanup() {
  # The probe rule is created OUT OF BAND, not by Terraform, so it is this
  # script's job to remove it. A script that creates AWS resources outside
  # Terraform creates things the teardown cannot see -- Week 12 left two
  # buckets behind exactly this way.
  aws_ events remove-targets --rule "$TEMP_RULE" --event-bus-name "$BUS" \
    --ids probe >/dev/null 2>&1
  aws_ events delete-rule --name "$TEMP_RULE" --event-bus-name "$BUS" >/dev/null 2>&1
}
trap cleanup EXIT

publish() {
  local entries
  entries=$(python3 - "$1" "$2" "$SOURCE" "$BUS" <<'PY'
import json, sys
dt, oid, source, bus = sys.argv[1:5]
print(json.dumps([{"Source": source, "DetailType": dt,
                   "Detail": json.dumps({"orderId": oid}), "EventBusName": bus}]))
PY
)
  aws_ events put-events --entries "$entries" --query 'Entries[0].EventId' --output text 2>/dev/null
}

seen_in_log() {
  local start_ms; start_ms=$(( ($(date +%s) - $3) * 1000 ))
  aws_ logs filter-log-events --log-group-name "$1" --start-time "$start_ms" \
    --filter-pattern "\"$2\"" --no-paginate --query 'length(events)' --output text 2>/dev/null | head -1
}

archive_count() {
  aws_ events describe-archive --archive-name "$ARCHIVE" --query EventCount --output text 2>/dev/null
}

echo "Preconditions"
state=$(aws_ events describe-archive --archive-name "$ARCHIVE" --query State --output text 2>/dev/null)
if [[ "$state" != "ENABLED" ]]; then
  echo "  archive $ARCHIVE is '$state', not ENABLED"; exit 2
fi
ok "archive $ARCHIVE is ENABLED"

consumer_arn=$(aws_ lambda get-function --function-name "${BUS}-consumer" \
  --query 'Configuration.FunctionArn' --output text 2>/dev/null)
[[ -z "$consumer_arn" || "$consumer_arn" == "None" ]] && { echo "  consumer not found"; exit 2; }
ok "consumer resolved"

# ---------------------------------------------------------------------------
# 1. Publish an event nothing matches, and confirm nothing matched it.
# ---------------------------------------------------------------------------
echo
echo "1. Publish '$TYPO' -- no rule matches it today"

before_count=$(archive_count)
replay_from=$(date -u -d '2 minutes ago' +%Y-%m-%dT%H:%M:%SZ)
order_id="replay-$(date +%s)"
event_id=$(publish "$TYPO" "$order_id")

if [[ -z "$event_id" || "$event_id" == "None" ]]; then
  broke "PutEvents returned no event id -- nothing was tested"
  echo; printf 'passed %d  failed %d  BROKEN %d\n' "$pass" "$fail" "$broken"; exit 3
fi
ok "published EventId ${event_id:0:8} (archive held ${before_count} events)"

echo "     waiting ${SETTLE}s to confirm nobody consumes it and the archive takes it..."
sleep "$SETTLE"

n=$(seen_in_log "$CONSUMER_LOG" "$event_id" 300)
if [[ "${n:-0}" -ne 0 ]]; then
  broke "the consumer already received it, so 'unmatched' is not true and the replay proves nothing"
  echo; printf 'passed %d  failed %d  BROKEN %d\n' "$pass" "$fail" "$broken"; exit 3
fi
ok "nothing consumed it -- delivered to nobody, as expected"

# EventCount on an archive is a periodic STATISTIC, not a live counter. A single
# read 60s after publishing showed 10 -> 10 and this check declared the event
# unarchived. It was archived; the number caught up at about three minutes.
# The guard was right to refuse -- "the archive is empty" and "the archive has
# not counted yet" lead to opposite conclusions about the replay result -- but
# one impatient read is evidence of neither. So poll, then decide.
after_count=$(archive_count)
for _ in $(seq 1 8); do
  [[ "${after_count:-0}" -gt "${before_count:-0}" ]] && break
  sleep 30
  after_count=$(archive_count)
done
if [[ "${after_count:-0}" -le "${before_count:-0}" ]]; then
  broke "archive count still ${after_count} after four minutes of polling; nothing to replay"
  echo; printf 'passed %d  failed %d  BROKEN %d
' "$pass" "$fail" "$broken"; exit 3
fi
ok "archive grew ${before_count} -> ${after_count} -- it archived an event no rule wanted"
echo "         The archive sits IN FRONT of the rules. It keeps what was"
echo "         published, not what was delivered."

# ---------------------------------------------------------------------------
# 2. NOW add a rule that matches it. This rule did not exist when the event
#    was published.
# ---------------------------------------------------------------------------
echo
echo "2. Add a rule matching '$TYPO' -- created AFTER the event was published"

pattern=$(python3 - "$SOURCE" "$TYPO" <<'PY'
import json, sys
print(json.dumps({"source": [sys.argv[1]], "detail-type": [sys.argv[2]]}))
PY
)
if ! aws_ events put-rule --name "$TEMP_RULE" --event-bus-name "$BUS" \
      --event-pattern "$pattern" --state ENABLED >/dev/null 2>&1; then
  broke "could not create the probe rule -- nothing was tested"
  echo; printf 'passed %d  failed %d  BROKEN %d\n' "$pass" "$fail" "$broken"; exit 3
fi
aws_ lambda add-permission --function-name "${BUS}-consumer" \
  --statement-id replay-probe --action lambda:InvokeFunction \
  --principal events.amazonaws.com >/dev/null 2>&1
aws_ events put-targets --rule "$TEMP_RULE" --event-bus-name "$BUS" \
  --targets "Id=probe,Arn=${consumer_arn}" >/dev/null 2>&1
ok "probe rule created and pointed at the consumer"

# ---------------------------------------------------------------------------
# 3. Replay the window and see which rules it follows.
# ---------------------------------------------------------------------------
echo
echo "3. Replay the window containing that event"

archive_arn=$(aws_ events describe-archive --archive-name "$ARCHIVE" --query ArchiveArn --output text 2>/dev/null)
bus_arn=$(aws_ events describe-event-bus --name "$BUS" --query Arn --output text 2>/dev/null)
replay_name="${BUS}-replay-$(date +%s)"
replay_to=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if ! aws_ events start-replay --replay-name "$replay_name" \
      --event-source-arn "$archive_arn" \
      --event-start-time "$replay_from" --event-end-time "$replay_to" \
      --destination "Arn=${bus_arn}" >/dev/null 2>&1; then
  broke "start-replay was rejected -- nothing was tested"
else
  ok "replay $replay_name started over ${replay_from} .. ${replay_to}"
  echo "     waiting ${SETTLE}s for it to complete and deliver..."
  sleep "$SETTLE"

  rstate=$(aws_ events describe-replay --replay-name "$replay_name" --query State --output text 2>/dev/null)
  if [[ "$rstate" != "COMPLETED" ]]; then
    broke "replay is '$rstate', not COMPLETED -- cannot conclude anything about delivery yet"
  else
    ok "replay COMPLETED"
    # MATCH ON THE PAYLOAD, NOT THE EVENT ID.
    #
    # A REPLAYED EVENT ARRIVES WITH A NEW EVENT ID. The first version of this
    # check grepped the consumer log for the ORIGINAL id, found nothing, and
    # reported that replay had not delivered -- while the delivery had plainly
    # happened moments earlier under a different id.
    #
    # That is not just a test bug, it is this week's subject: the event id is
    # the join key between CloudTrail (who published it) and the archive (what
    # was in it). Replay mints a new one, so a replayed event cannot be traced
    # back to the principal who originally published it. The attribution chain
    # breaks precisely where an incident would need it.
    #
    # orderId survives the round trip, so that is what identifies the copy.
    n=$(seen_in_log "$CONSUMER_LOG" "$order_id" 900)
    if [[ "${n:-0}" -gt 0 ]]; then
      ok "the consumer received ${event_id:0:8} -- ON REPLAY, via a rule that did not exist when it was published"
      echo "         A replay follows the rules that exist NOW. An event that was"
      echo "         delivered to nobody has now been delivered to somebody."
      echo "         That is not a time machine -- it is re-publishing old events"
      echo "         into today's system, with today's consequences."
    else
      bad "the consumer did not receive it; replay did not deliver through the new rule"
    fi
  fi
fi

echo
echo "----------------------------------------------------------------"
printf 'passed %d   failed %d   BROKEN %d\n' "$pass" "$fail" "$broken"
if (( broken > 0 )); then
  echo; echo "BROKEN checks did not run. Fix the precondition and run again."
  exit 3
fi
(( fail > 0 )) && { echo "Behaviour did not match what the post intends to claim."; exit 1; }
echo "All checks ran and behaved as described."
