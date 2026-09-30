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
| 04 | `04-client-view.png` | testing | What a client received across both deployments | **Terminal** - the only surface showing what a *client* got | during the shift |
| 07 | `07-alb-target-groups.png` | apply | **What was deployed:** the ALB with both target groups and their health | **AWS console** | the apply |
| 08 | `08-ecs-cluster.png` | apply | **What was deployed:** the ECS cluster, the service and its running task | **AWS console** | the apply |
| 05 | `05-failed-deploy-healthcheck.png` | testing | The bad version rejected at the target group -- `Target.ResponseCodeMismatch`, traffic never moved | **AWS console** | bad v3 deploy |
| 06 | `06-cost-explorer.png` | Cost | Cost Explorer for the run window, by service | **AWS console** | ~24h after teardown |

Eight slots. Seven and eight were added on 2026-09-30, after Jay asked "no need to show
screenshots on what we deployed?" He was right: the plan had one console shot of the service
and nothing showing the resources themselves, so a reader asking *what did they build* got a
table and no picture.

**Slots 07 and 08 are the answer to "what was deployed".** Every future week needs at least
one, and `check_figures_before_destroy.py` blocks teardown until every declared slot is
captured or retired -- because the resources stop existing the moment the destroy applies.

## Method is part of the plan

Weeks 19 and 20 shipped with no AWS console screenshots because the console session lapsed
and each figure quietly became a typeset card. `capture.py` now mints its own console
session from the CLI's temporary credentials, so a lapsed session is invisible and nobody
is asked to sign in.

Jay's standing rule: **"I always want the screenshots from the real capture."**

## Deviation, recorded 2026-09-29 after the build

Slot 05 was planned as "the deployment rolled back automatically, with the alarm that
caused it." **That is not what happened, so it is not what the figure shows.**

The deliberately bad version failed its target group health check -- 404 against a matcher
of 200 -- so ECS stopped the tasks and traffic never moved. No client request reached the
broken version, so the 4xx alarm never breached and never rolled anything back. 214 requests
during the attempt, all served by the healthy version.

Slot 04 also shifted meaning. It was planned as "a mix of v1 and v2". With one task and the
plain BLUE_GREEN strategy there is no mix -- the listener rule switches and every subsequent
request gets the new version. The capture shows the cutover instant instead, at t+182s.

Both are better findings than the ones planned. Neither is a reason to relabel a figure as
the thing it was supposed to be.

## If the build deviates from this plan

Change this file first, then capture. A plan edited afterwards to match what was captured
is a description, and it prevents nothing.
