# Week 27 figure plan

Written before deploying. `scripts/check_figures_before_destroy.py` reads this
file and refuses teardown while a declared slot is missing.

Target is 4-7 figures in the published post.

| # | File | Section | What it shows | Source | When |
|---|------|---------|---------------|--------|------|
| 01 | `01-cache-created.png` | Implementation | The serverless cache, engine Valkey, status available | **AWS console** | after apply |
| 02 | `02-hcp-apply.png` | Implementation | The remote apply with OIDC, no stored keys | HCP | after apply |
| 03 | `03-ecpu-by-size.png` | Validation | **The week.** Same request count at 1/10/100 KB, ECPUs consumed for each | **Real terminal** | after the run |
| 04 | `04-cloudwatch-ecpus.png` | Validation | CloudWatch `ElastiCacheProcessingUnits`, three plateaus at the same request rate | **AWS console** | after the run |
| 05 | `05-cache-metrics.png` | Validation | `BytesUsedForCache` against the 100 MB minimum | **AWS console** | after the run |
| 06 | `06-destroyed.png` | Cleanup | Nothing left, queried against the API | **Real terminal** | after destroy |
| 07 | `07-cost.png` | Security and Cost | Measured cost from Cost Explorer | AWS console | **after teardown + ~1 day** |

## Console deep links

    https://us-east-1.console.aws.amazon.com/elasticache/home?region=us-east-1#/valkey
    https://us-east-1.console.aws.amazon.com/cloudwatch/home?region=us-east-1#metricsV2

Find others by reading the `href` off the console's left nav with Playwright
over the existing CDP session, not by guessing fragments.
