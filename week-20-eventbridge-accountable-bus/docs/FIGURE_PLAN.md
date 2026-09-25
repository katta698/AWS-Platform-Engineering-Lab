# Week 20 — figure plan, written BEFORE anything is captured

This file exists because of Week 18, and it worked in Week 19, so it is now how every
week starts.

Week 18 captured ten screenshots and then went looking for somewhere to put them. That
search is what broke the post: a `kubectl` listing of live namespaces landed under a step
that runs *before* the cluster exists. The same class of error was fixed three times, and
Week 17 turned out to have shipped it too.

The cause was never carelessness about one image. The post is organised by **topic**, the
captures are numbered by **time**, and a screenshot has a topically perfect home and a
temporally impossible one. Topic wins when you are placing an image you already have.

So the order is decided here, first, in narrative order. Capture fills these slots.

## Rules this plan obeys

1. **Nothing above the deploy step may show live state.** Steps before the deploy produce
   Terraform and decisions, not infrastructure. Enforced in CI by
   `check_figure_order.py` in the blog repo — it fails the build, so a violation cannot
   reach a reader even if this file is ignored.
2. **`01` is the HCP run, captured AT the apply, before any console shot.** Standing
   instruction, re-confirmed with visible frustration. Week 19 nearly lost it entirely.
3. **Numbers are assigned here and never reused.** A capture not worth publishing is
   retired to `UNUSED.txt` with a reason, not recycled.
4. **A genuine pre-deploy prerequisite is allowed but must be declared** with
   `<figure class="screenshot" data-prereq>`.

## The slots

| # | Filename | Section | What it must show | Exists only after |
|---|----------|---------|-------------------|-------------------|
| 01 | `01-hcp-run-applied.png` | **Step 4 — Deploy it** | HCP run list for `week-20-dev`, applied, with the resource count | the apply |
| 02 | `02-bus-configured.png` | Step 4 | **AWS console.** The bus with schema discovery on, and the four rules &mdash; two of them Managed | the apply |
| 03 | `03-discovered-schema.png` | Step 5 | A schema the discoverer inferred from real traffic — the shape producers actually send | first events published |
| 04 | `04-cloudtrail-data-event.png` | Step 5 | **AWS console.** The trail's data-event selector: management events off, `AWS::Events::EventBus` scoped to this bus | logging enabled |
| 05 | `05-cloudtrail-record.png` | Step 5 | **Terminal.** The `PutEvents` record itself, caller identity and the redacted payload. The trail writes to S3 only, so no console view of a record exists | an event published |
| 06 | `06-the-event-that-matched-nothing.png` | Verifying | **The money shot.** `PutEvents` returning HTTP 200 and an EventId, beside the consumer logs showing nothing arrived | the unmatched publish |
| 07 | `07-detection-catches-it.png` | Verifying | The catch-all rule recording the event the specific rule ignored — and what that second delivery costs | detection deployed |
| 08 | `08-replay-follows-current-rules.png` | Challenges | **AWS console.** The archive and its replay history: 13 events, two replays `Completed` | a replay |
| 12 | `12-replay-delivered-through-a-new-rule.png` | Challenges | **Terminal.** The proof the console does not carry: the replay delivered through a rule created AFTER the event, under a new event id | archive + a rule change |
| 09 | `09-dlq-caught-a-failure.png` | Challenges | A real failed delivery sitting in the DLQ, not a synthetic message | a deliberately broken target |
| 10 | `10-cost-explorer.png` | Cost | Cost Explorer for the run window, by usage type | ~24h after teardown |
| 11 | `11-alarm-email-consumer-errors.png` | Verifying | The OK -> ALARM notification a human actually receives | an alarm firing |

**Slot 11 was added during the build, before capture, per the rule at the bottom of
this file.** It exists because the alarm email stopped being a human-dependency item:
Gmail is reachable from this session, so the notification can be read over an API,
redacted, and rendered — rather than photographed off a phone. That closes the one
gap in the screenshot set that had survived twenty weeks.

**Slots 07 and 09 are covered by `06`.** The experiment output shows the matched path
delivering, the catch-all recording the unmatched event, and the Lambda on-failure queue
going 1 -> 2 while the EventBridge DLQ stays at 0 &mdash; all in the same run, on the same
evidence. More figures of the same log would be padding; they are declared in
`UNUSED.txt` rather than captured for the sake of the count.

## Capture method is part of the plan (added 2026-09-24)

Every slot above names **how** it is captured, not only what it shows. That column exists
because Weeks 19 and 20 shipped with no AWS console screenshots at all: the console
session lapsed, and each figure quietly became a typeset card rendered from CLI output.
The content was real; nothing in the pipeline required it to be, and a reader cannot tell
a rendered card from a captured screen.

Jay's standing rule, 2026-09-24: **"I always want the screenshots from the real capture."**

A terminal card is legitimate only where a terminal is the honest surface for that
evidence &mdash; slot 05, for instance, because the trail writes to S3 and no console view
of a single record exists. It is never a stand-in for a console view this plan asked for.

A lapsed console session is not a reason to ask anyone to sign in. `capture.py` mints its
own session from the CLI's temporary credentials on every console URL.

## Order check

Every slot is at or below the deploy step — Week 20 has no genuine pre-deploy console
state, so there is no `data-prereq` figure this week. `python scripts/check_figure_order.py
week-20` against the finished post must return `[ ok ]`, and `check_week_complete.py` must
report every capture either referenced or listed in `UNUSED.txt`.

**Slot 12 was added on 2026-09-24, after capture, and that is a deviation from the
rule at the bottom of this file.** Jay asked for 08 to be retaken from the console. The
console records that a replay completed; it does not show that the replay followed a rule
created after the event, or that the event id changed. Replacing the terminal output would
have removed the only evidence for the week's fourth finding, so the console shot took 08
and the proof took a new number rather than reusing a retired one.

## If the build deviates from this plan

Change this file first, then capture. A plan edited afterwards to match what was captured
is not a plan — it is a description, and it prevents nothing.
