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
| 02 | `02-event-bus-configured.png` | Step 4 | The bus in the console with the archive and the schema discoverer both ON | the apply |
| 03 | `03-discovered-schema.png` | Step 5 | A schema the discoverer inferred from real traffic — the shape producers actually send | first events published |
| 04 | `04-cloudtrail-data-events.png` | Step 5 | CloudTrail data-plane logging enabled on the bus, and a `PutEvents` record with a caller identity | logging enabled + an event |
| 05 | `05-matched-path-delivered.png` | Verifying | The happy path: rule matched, consumer invoked, event visible in its logs | first matched event |
| 06 | `06-the-event-that-matched-nothing.png` | Verifying | **The money shot.** `PutEvents` returning HTTP 200 and an EventId, beside the consumer logs showing nothing arrived | the unmatched publish |
| 07 | `07-detection-catches-it.png` | Verifying | The catch-all rule recording the event the specific rule ignored — and what that second delivery costs | detection deployed |
| 08 | `08-replay-to-current-rules.png` | Challenges | A replay re-delivering to the rules that exist NOW, not the ones that existed when archived | archive + a rule change |
| 09 | `09-dlq-caught-a-failure.png` | Challenges | A real failed delivery sitting in the DLQ, not a synthetic message | a deliberately broken target |
| 10 | `10-cost-explorer.png` | Cost | Cost Explorer for the run window, by usage type | ~24h after teardown |

## Order check

Every slot is at or below the deploy step — Week 20 has no genuine pre-deploy console
state, so there is no `data-prereq` figure this week. `python scripts/check_figure_order.py
week-20` against the finished post must return `[ ok ]`, and `check_week_complete.py` must
report every capture either referenced or listed in `UNUSED.txt`.

## If the build deviates from this plan

Change this file first, then capture. A plan edited afterwards to match what was captured
is not a plan — it is a description, and it prevents nothing.
