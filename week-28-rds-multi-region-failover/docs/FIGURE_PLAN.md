# Week 28 figure plan

Written before deploying. `scripts/check_figures_before_destroy.py` reads this
file and refuses teardown while a declared slot is missing.

Target is 4-9 figures in the published post. Slot 01 is the HCP run, every
week, captured at the moment of the apply -- the run history is the only
surviving record of how a deploy went and it goes when the workspace does.

| # | File | Section | What it shows | Source | When |
|---|------|---------|---------------|--------|------|
| 01 | `01-hcp-runs.png` | Implementation | The HCP run: plan finished, 17 to create, applying | HCP | **at the moment of the apply** |
| 02 | `02-hcp-variables.png` | Implementation | Workspace variables — OIDC auth, role ARN masked, no stored keys | HCP | at the apply |
| 03 | `03-primary-and-replica.png` | Implementation | Both instances: primary in us-east-1, replica in us-west-2, replication established | **AWS console** | after apply |
| 04 | `04-region-switch-plan.png` | Implementation | The ARC Region switch plan and its promote step | **AWS console** | after apply |
| 05 | `05-replication-lag.png` | Validation | `ReplicaLag` under write load — the data-loss window, in seconds | **AWS console** | during the write load |
| 06 | `06-failover-timed.png` | Validation | **The week.** Promotion timed against the clock, and replication gone afterwards | **Real terminal** | after the plan runs |
| 07 | `07-failover-evidence.png` | Validation | CloudTrail showing the Region switch execution identity calling PromoteReadReplica, and the RDS event log timeline | **Real terminal** | after the failover |
| 08 | `08-destroyed.png` | Cleanup | Nothing left in either region, queried against the API | **Real terminal** | after destroy |
| 09 | `09-cost.png` | Security and Cost | Measured cost from Cost Explorer, with the ARC plan line itemised | AWS console | **after teardown + ~1 day** |

Figure 09 carries the week's open question: the $70/plan/month proration
granularity is undocumented, so the plan line is the figure's point.

Figure 07 exists because the first draft had no evidence the failover ever
happened -- only a terminal printing numbers this repo wrote itself. RDS
events and CloudTrail are AWS's record, not ours, and they survive the
resources being deleted.

## Console deep links

    https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1#databases:
    https://us-west-2.console.aws.amazon.com/rds/home?region=us-west-2#databases:
    https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#metricsV2

ARC Region switch console path is not guessed: read the `href` off the console's
left nav with Playwright over the existing CDP session before capturing 03.
