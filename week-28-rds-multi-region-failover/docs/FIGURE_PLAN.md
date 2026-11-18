# Week 28 figure plan

Written before deploying. `scripts/check_figures_before_destroy.py` reads this
file and refuses teardown while a declared slot is missing.

Target is 4-7 figures in the published post.

| # | File | Section | What it shows | Source | When |
|---|------|---------|---------------|--------|------|
| 01 | `01-primary-and-replica.png` | Implementation | Both instances: primary in us-east-1, replica in us-west-2, replication established | **AWS console** | after apply |
| 02 | `02-hcp-apply.png` | Implementation | The remote apply with OIDC, no stored keys, two aliased providers | HCP | after apply |
| 03 | `03-region-switch-plan.png` | Implementation | The ARC Region switch plan and its promote step | **AWS console** | after apply |
| 04 | `04-replication-lag.png` | Validation | `ReplicaLag` under write load — the data-loss window, in seconds | **AWS console** | during the write load |
| 05 | `05-failover-timed.png` | Validation | **The week.** Promotion timed against the clock, and replication gone afterwards | **Real terminal** | after the plan runs |
| 06 | `06-destroyed.png` | Cleanup | Nothing left in either region, queried against the API | **Real terminal** | after destroy |
| 07 | `07-cost.png` | Security and Cost | Measured cost from Cost Explorer, with the ARC plan line itemised | AWS console | **after teardown + ~1 day** |

Figure 07 carries the week's open question: the $70/plan/month proration
granularity is undocumented, so the plan line is the figure's point.

## Console deep links

    https://us-east-1.console.aws.amazon.com/rds/home?region=us-east-1#databases:
    https://us-west-2.console.aws.amazon.com/rds/home?region=us-west-2#databases:
    https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#metricsV2

ARC Region switch console path is not guessed: read the `href` off the console's
left nav with Playwright over the existing CDP session before capturing 03.
