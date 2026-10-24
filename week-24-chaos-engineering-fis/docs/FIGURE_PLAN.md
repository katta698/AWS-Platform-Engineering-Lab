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
| 09 | `09-recovery-run.png` | Challenges | The unguarded run: impact, then ECS putting tasks back. The baseline | Rendered card |
| 10 | `10-fast-vs-typical.png` | Challenges | **The week.** Both guarded runs on one timeline: identical fault, damage window 10x apart | Rendered card |
| 11 | `11-summary-output.png` | Challenges | `summarise.py` output across all three runs | Rendered card |
| 12 | `12-destroyed.png` | Cleanup | Nothing left: no cluster, no ALB, no experiment templates | Rendered card |
| 13 | `13-cost.png` | Cost | The billed figure by usage type — FIS action-minutes separated from Fargate | Rendered card — after teardown |

## The two that carry the week

**07** sets it up. Two alarms, same metric, same target group, differing only in
patience. A reader should look at that and not yet see the problem.

**10** is the payoff. The same fault, injected twice, with the damage window
measured. If the numbers land anywhere near the modelled 60s versus 605s, the
chart makes the argument without a caption.

## Deliberately not captured

A FIS **experiment report** would be a tidy figure and costs **$5 each**. The
same information is in the experiment detail page and the recorded CSV, so it
is not worth 5x the rest of the week's compute.
