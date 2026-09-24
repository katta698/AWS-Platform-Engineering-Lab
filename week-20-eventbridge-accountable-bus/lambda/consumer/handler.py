"""Consumer for the accountable bus.

Its job is to be *evidence*. Everything this week claims about delivery is
proven by what does or does not appear in this function's log group:

  - a matched event arrives here and is logged with its event id
  - an unmatched event never arrives at all, which is the whole point
  - a poison event fails here, exhausts the retry policy, and lands in the DLQ

WHY IT LOGS THE EVENT ID SPECIFICALLY
The event id is the only value that appears in all three places: the PutEvents
response the publisher got back, the CloudTrail data event (which carries the
identity but redacts the payload), and here (which carries the payload but no
identity). It is the join key for the investigation, and Week 20's whole
argument is that you need both halves.
"""
import json
import logging
import os

log = logging.getLogger()
log.setLevel(logging.INFO)

# A detail-type that makes this function fail on purpose, so the DLQ can be
# proven with a real delivery failure rather than a message pushed into the
# queue by hand. A DLQ that has only ever seen synthetic traffic has not been
# tested.
POISON_DETAIL_TYPE = os.environ.get("POISON_DETAIL_TYPE", "order.poison")


def handler(event, context):
    detail_type = event.get("detail-type", "<none>")
    event_id = event.get("id", "<none>")
    source = event.get("source", "<none>")

    log.info(
        "received event_id=%s source=%s detail_type=%s",
        event_id, source, detail_type,
    )

    if detail_type == POISON_DETAIL_TYPE:
        # Raising is what makes EventBridge treat this as a failed delivery.
        # With retry_policy maximum_retry_attempts = 0 on the target, the very
        # next stop is the DLQ -- no waiting out an exponential backoff to see
        # whether the mechanism works.
        log.error("poison event_id=%s -- failing deliberately", event_id)
        raise RuntimeError(f"deliberate failure for event {event_id}")

    log.info("processed event_id=%s payload=%s", event_id, json.dumps(event.get("detail", {})))
    return {"ok": True, "event_id": event_id}
