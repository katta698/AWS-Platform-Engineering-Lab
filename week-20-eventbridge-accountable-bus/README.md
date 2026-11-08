# Week 20 — An Accountable Event Bus

**What you build:** Build an event bus you can actually interrogate: who published, what was delivered, what matched nothing, and what happens to an event nobody wanted.

**Status: scaffolded 2026-09-24, `terraform validate` clean. Nothing applied yet.**

An event bus is the easiest thing in AWS to deploy and one of the hardest to
interrogate. Publishing succeeds whether or not anything is listening:
`PutEvents` returns **HTTP 200 and an event id** for an event that no rule
matches and nobody consumes. There is no error, no default metric, and nothing
that records a decision was made to discard it.

This week adds the four mechanisms that make a bus answerable, then tries to
break the one everybody assumes rather than tests.

| | |
|---|---|
| **Cost** | no hourly meter · destroyed |
| **Provisioning** | Terraform · HCP · EventBridge · CloudTrail |

> **Status:** built, validated and destroyed.

## 1. Prerequisites

| Requirement | Detail |
|---|---|
| AWS account | Permission for EventBridge, Lambda, SQS, CloudTrail, CloudWatch and S3 |
| Terraform | >= 1.10 |
| HCP Terraform | Workspace with OIDC to AWS. No static keys |
| CloudTrail | Data events are **off by default** and billed per event — scope the selector by bus ARN |
| Region | `us-east-1` |

## 2. Source files

### Layout
```
docs/FIGURE_PLAN.md          screenshot slots, written BEFORE any capture
lambda/consumer/handler.py   the evidence trail; fails on purpose for the DLQ test
scripts/prove_unmatched.sh   the experiment
scripts/cleanup.sh           teardown verification, including the quiet chargers
terraform/
  modules/event_bus          bus, archive, discoverer, CloudTrail data events
  modules/consumers          rules, consumer, DLQ, catch-all, alarms
  environments/dev           HCP workspace week-20-dev
```

## 3. Deploy

The workspace is VCS-connected, so an apply does not run from a
checkout: `terraform apply` is refused with
`Error: Apply not allowed for workspaces with a VCS connection`.

```bash
# on the connected branch
git push
```

The push queues a plan in the `week-20-dev` workspace (project **AWS Platform Lab**, organization `Katta`). Confirm
the apply on its run page.

## 4. Run it

```bash
./scripts/prove_replay.sh
```

Does a replay re-deliver to the rules that existed when the event was archived, or to the rules that exist now? It matters because people reach for replay during an incident: "we lost an hour of events, replay them." If replay followed the ORIGINAL routing, that is a time machine.

```bash
./scripts/prove_unmatched.sh
```

What happens to an event that no rule matches? The advertised answer is "it is discarded". The interesting part is how thoroughly indistinguishable that is from success: PutEvents returns HTTP 200 and an event id, the publisher's code carries on, and nothing anywhere says a decision was made to drop it. THE RULE THIS SCRIPT IS BUILT AROUND, carried from two prior weeks.

## 5. Validation

| Test | Expected |
|---|---|
| Matching event reaches the consumer | Delivered and processed |
| Typo event (`order.crated`) is published | 200, matched by nothing |
| CloudTrail attributes the publisher | Caller recorded |
| Rule-target DLQ catches a failing consumer | Message lands in DLQ |
| Consumer-error alarm fires | Notification sent |
| Replay re-delivers an archived event | Follows current rules |

The results recorded when this lab was built are in the article.

## 6. Cleanup

### Teardown
```bash
# destroy via HCP, then verify
./scripts/cleanup.sh
```

`cleanup.sh` checks four things a "delete the bus" sweep misses: the **archive**
(not deleted with the bus, and its storage keeps billing), **discovered schemas**
(they outlive the discoverer), the **log-group resource policy** (account-level,
invisible in the log-group view), and **rules left on the `default` bus** — which
is where they land if `event_bus_name` is ever omitted.

## Cost

### Cost — the opposite shape to Weeks 18 and 19
**There is no hourly meter anywhere.** No control plane, no NAT, no node. Weeks
18 and 19 billed $0.17–$0.22/hr from the moment they existed; this bills per
event, and lab volume is thousands.

| Item | Rate |
|---|---|
| Custom events | $1.00 / M ingested |
| Schema discovery | **free to 5M events/month**, then $1.00/M in 8 KB chunks |
| Archive | $0.10/GB processing + **$0.023/GB/month storage** |
| Replay | $1.00 / M |
| CloudTrail data events | billed per event |

**Expected total: cents.** Teardown still matters, but for a different reason —
the archive, the trail and the discoverer keep charging quietly and
indefinitely. Small and permanent is easier to miss than large and obvious.

## Troubleshooting

**`Order.crated` — published once, matched by nothing, consumed by nobody — acquired a full OpenAPI definition beside the real events**.
Schema discovery documents what producers *actually send*, and at the wire level there is no difference between a new event type and a bug.
*Fix:* None available — discovery is not validation, and nothing rejected any of them. EventBridge accepted every event regardless of the registry's contents.

**A DLQ was attached to the rule target, an event the consumer fails on was published, and the queue stayed empty**.
The EventBridge DLQ covers "I could not hand this over". A target that *accepts* an event and then fails has succeeded as far as the rule is concerned.
*Fix:* A separate on-failure destination on the function itself — two failure modes, two queues.

**A replayed event was delivered through a rule that did not exist when it was first published**.
Replay follows *current* rules, issues new event ids, and carries today's consequences.
*Fix:* Treat replay as publishing, not as time travel.

## References

### Sources
- [Logging EventBridge API calls with CloudTrail](https://docs.aws.amazon.com/eventbridge/latest/userguide/logging-using-cloudtrail.html) — the data-event table, the redaction note, and the cross-account caveat
- [EventBridge data plane logging to CloudTrail](https://aws.amazon.com/about-aws/whats-new/2026/05/amazon-eventbridge-data-aws-cloudtrail/) — 4 May 2026
- [Amazon EventBridge pricing](https://aws.amazon.com/eventbridge/pricing/)
- [EventBridge Schemas](https://docs.aws.amazon.com/eventbridge/latest/schema-reference/what-is-eventbridge-schemas.html)

## What it builds

```
week20-bus  (custom bus -- NOT `default`)
├── archive                     can I get the event back?
├── schema discoverer           what did it actually look like?
├── CloudTrail data events      who published it?        <- new 4 May 2026
│
├── rule: week20-bus-orders     -> consumer Lambda -> DLQ on failure
└── rule: week20-bus-catch-all  -> log group
        the only way to count events that matched no other rule
```

## The thing being deliberately broken

Publish an event whose `detail-type` has **one transposed letter** —
`order.crated` instead of `order.created`. That is the whole fault.

`PutEvents` returns 200 and an event id. The publisher's code carries on. The
consumer never sees it. No alarm fires, because **EventBridge publishes
`MatchedEvents` per rule and has no metric at all for "matched no rule"**.

`scripts/prove_unmatched.sh` establishes delivery works on the same run first —
"nothing arrived" only means something once "something can arrive" has been
shown — then publishes the typo, then checks the DLQ with a real failed
delivery rather than a message pushed into the queue by hand.

It reports **three** outcomes. A check whose precondition did not hold is
`BROKEN`, never a pass. Week 18 published a test that scored two of four green
against pods that never started; Week 19's twice raced a controller faster than
its own observation window. Both times the fix was to measure something that
cannot be undone.

## What is already known before building (verified live 2026-09-22)

- **CloudTrail redacts the payload.** A data event carries the caller, the IP,
  the source, the detail-type and the event id, then `"detail":
  "HIDDEN_DUE_TO_SECURITY_REASONS"`. It tells you **who** and **when**, never
  **what**. The archive holds the payload and carries no identity. The two join
  on the event id, and neither answers "what happened" alone.
- **Cross-account attribution goes to the caller, not the bus owner.** If
  another account publishes to your bus through a resource policy, *their*
  account receives the CloudTrail data event and yours does not. Owning the bus
  does not mean seeing who wrote to it.
- **The schema registry does not enforce anything.** EventBridge accepts an
  event that violates every schema it holds. This is discovery, not validation.
- **A replay re-delivers to the rules that exist now**, not the rules that
  existed when the event was archived.
- **Everything is billed per 64 KB chunk** — a 256 KB event bills as four.
