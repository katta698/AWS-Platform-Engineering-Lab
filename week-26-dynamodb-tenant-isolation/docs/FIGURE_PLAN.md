# Week 26 figure plan

**Written late, and that is the point.** Weeks 19-25 each wrote this file
before deploying. Week 26 did not, and the consequence was exactly the one
`check_figures_before_destroy.py` was built to prevent after week 21: the
stack was destroyed with no AWS console figure taken, and Jay had to ask
"so no screenshots needed from aws console for this lab?" to surface it.

A check cannot fail on slots that were never declared. No plan meant no
slots meant nothing to fail on, and the week's own `cleanup.sh` did not call
the check either. This file closes the first half of that; the `cleanup.sh`
change closes the second.

Target is **4-7 figures** in the published post (Master Standard §4).

| # | File | Section | What it shows | Source | When |
|---|------|---------|---------------|--------|------|
| 01 | `01-the-cluster.png` | Implementation | Three `dax.t3.small` nodes, one per AZ, cluster available | **Real terminal** | **DONE 2026-11-08** |
| 02 | `02-isolation-truth-table.png` | Validation | **The week.** All ten cases, expected against actual, including `cross-tenant-direct` denied and `cross-tenant-dax` allowed | **Real terminal** | **DONE 2026-11-08** |
| 03 | `03-hcp-apply.png` | Implementation | The remote apply, run with OIDC dynamic credentials | HCP | **DONE 2026-11-08** |
| 04 | `04-hcp-variables.png` | Implementation | `TFC_AWS_PROVIDER_AUTH` and a write-only run-role ARN - no stored keys | HCP | **DONE 2026-11-08** |
| 05 | `05-dax-cluster-console.png` | Implementation | The DAX cluster as the console shows it: three nodes, three AZs, status available | **AWS console** | redeploy 2026-11-08 |
| 06 | `06-pooled-table-items.png` | Validation | **Both tenants' items in one table.** The thing the whole lab is about, seen in the console rather than asserted | **AWS console** | redeploy 2026-11-08 |
| 07 | `07-tenant-policy.png` | Architecture | The live IAM policy on the `alpha` role, with the `LeadingKeys` + `Null` + `Select` condition block as IAM stores it | **AWS console** | redeploy 2026-11-08 |
| 08 | `08-cost.png` | Security and Cost | Measured DAX cost from Cost Explorer | AWS console | **after 2026-11-09** - cost slots cannot be captured until ~a day after teardown |

## The console URL that cost a redeploy

The DAX cluster list is at:

    https://us-east-1.console.aws.amazon.com/dynamodbv2/home?region=us-east-1#dax-clusters

Recorded here because guessing it wrong is what lost the first window. Four
fragments were tried on 2026-11-08 - `#cache-clusters`, `#dax`,
`#dax-clusters`, `#clusters` - and `#dax-clusters` is correct. It was in the
set, but its probe was written to a `/tmp` path that Windows Python cannot
resolve, so it never saved and was never looked at. The conclusion "the
fragment keeps resolving to Invalid URL" was drawn from the two that had
been viewed, and was wrong.

The reliable way to find a console deep link, rather than guessing: read the
`href` off the live console's own nav with Playwright over the existing CDP
session.

## Why 06 is not redundant with 02

Figure 02 is the finding and is the stronger evidence, because it was
produced under `set -x` and declares each expectation before running. But it
is a terminal, and a terminal can be made to say anything by someone who has
not read the script beside it. Figure 06 shows the same pooled table in
AWS's own interface, with both tenants' partition keys visible in one list,
and needs no trust in my tooling at all.
