# Week 21 — figure plan, written BEFORE anything is captured

Short post this week (~1,100 words), so the figure set is small and every slot must earn
its place. Capture method is named per slot, because that is the column that drifted for
two weeks before anyone noticed.

## Rules this plan obeys

1. **Nothing above the deploy step may show live state.** Enforced by
   `check_figure_order.py` in the blog repo.
2. **`01` is the HCP run, captured AT the apply.**
3. **Numbers are assigned here and never reused.**
4. **Real captures only.** A terminal card is allowed only where a terminal is the honest
   surface for that evidence, and the slot says so.

## The slots

| # | Filename | Section | What it must show | Method | Exists only after |
|---|----------|---------|-------------------|--------|-------------------|
| 01 | `01-hcp-run-applied.png` | How We Built It — apply | HCP run for `week-21-dev`, applied, resource count | **HCP console** | the apply |
| 02 | `02-ecs-service-blue-green.png` | apply | ECS service showing deployment strategy BLUE_GREEN, bake time, both target groups | **AWS console** | the apply |
| 03 | `03-traffic-shifting.png` | testing | A deployment mid-shift: canary percentage, old and new task sets both live | **AWS console** | v2 deploy |
| 04 | `04-curl-version-mix.png` | testing | A loop against the ALB returning a mix of v1 and v2 | **Terminal** — the only surface that shows what a *client* got | during the shift |
| 05 | `05-alarm-rollback.png` | testing | The deployment rolled back automatically, with the alarm that caused it | **AWS console** | bad v3 deploy |
| 06 | `06-cost-explorer.png` | Cost | Cost Explorer for the run window, by service | **AWS console** | ~24h after teardown |

Six slots against Week 20's nine, deliberately.

## Method is part of the plan

Weeks 19 and 20 shipped with no AWS console screenshots because the console session lapsed
and each figure quietly became a typeset card. `capture.py` now mints its own console
session from the CLI's temporary credentials, so a lapsed session is invisible and nobody
is asked to sign in.

Jay's standing rule: **"I always want the screenshots from the real capture."**

## If the build deviates from this plan

Change this file first, then capture. A plan edited afterwards to match what was captured
is a description, and it prevents nothing.
