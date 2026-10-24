# Week 24 figure plan

| # | File | Section | What it shows | Source |
|---|------|---------|---------------|--------|
| 01 | `01-before-state.png` | How We Built It | FIS console with no experiment templates — the starting line | AWS console |
| 02 | `02-terraform-layout.png` | How We Built It | The files that build the week, each with its job and line count | Rendered card |
| 03 | `03-hcp-workspace-vars.png` | How We Built It | HCP workspace variables and OIDC — no static keys | HCP |
| 04 | `04-hcp-plan.png` | How We Built It | The plan, read before applying | HCP |
| 05 | `05-hcp-applied.png` | How We Built It | Applied, with the resource count | HCP |
| 06 | `06-service-healthy.png` | How We Built It | Target group with 4 healthy targets, before anything is broken | AWS console |
| 07 | `07-two-alarms.png` | How We Built It | Both alarms side by side — same metric, 60s/1 vs 300s/2. **The experiment is this difference** | AWS console |
| 08 | `08-experiment-templates.png` | How We Built It | Three templates, and the stop condition on each | AWS console |
| 09 | `09-metric-that-never-moved.png` | Challenges | **Finding 1.** CloudWatch showing `UnHealthyHostCount` flat at 0 across a window where the service demonstrably halved | AWS console |
| 10 | `10-six-completed-actions.png` | Challenges | **Finding 3.** The FIS experiment detail: six kill rounds, all "Action was completed", only the first stopped a task | AWS console |
| 11 | `11-dip-vs-sampling.png` | Challenges | **Finding 4.** The per-second recording against the 1-minute metric: a 17s outage that CloudWatch never saw | Rendered card |
| 12 | `12-destroyed.png` | Cleanup | Nothing left: no cluster, no ALB, no experiment templates | Rendered card |
| 13 | `13-cost.png` | Cost | The billed figure by usage type — FIS action-minutes separated from Fargate | Rendered card — after teardown |

## The two that carry the week

**09** is the one a reader should not be able to argue with. Two metrics, one
window, the same service: capacity halves and the metric everyone would have
alarmed on reports zero the whole way through.

**10** is the punchline. Six actions, six green "Action was completed", and
only the first of them did anything at all. The console gives no hint which
five were no-ops.

## Changed from the original plan

The original figure 10 was to be "fast versus typical, damage windows 10x
apart". That comparison could not be measured -- see `FINDINGS.md`. The fault
heals in 17 seconds, the metric samples every 60, and the FIS action
completes in 373 milliseconds, so no stop condition could act at all. The
figures now carry the four findings that replaced it.

## Deliberately not captured

A FIS **experiment report** would be a tidy figure and costs **$5 each**. The
same information is in the experiment detail page and the recorded CSV, so it
is not worth 5x the rest of the week's compute.
