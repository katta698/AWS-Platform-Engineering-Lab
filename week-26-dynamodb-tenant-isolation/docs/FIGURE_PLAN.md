# Week 26 figure plan

Written so the week knows what it must capture before anything is destroyed.
`scripts/check_figures_before_destroy.py` reads this file and refuses a
teardown while a declared slot is missing, so a figure that is wanted should
be listed here before the deploy, not after.

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

## Console deep links

The DAX cluster list:

    https://us-east-1.console.aws.amazon.com/dynamodbv2/home?region=us-east-1#dax-clusters

The item explorer for a table:

    https://us-east-1.console.aws.amazon.com/dynamodbv2/home?region=us-east-1#item-explorer?table=<name>&maximize=true

An inline role policy:

    https://us-east-1.console.aws.amazon.com/iam/home#/roles/details/<role>/editPolicy/<policy>?step=addPermissions

These are worth recording because the console's URL fragments are not
documented and not guessable. To find another, read the `href` off the
console's own left nav with Playwright over an existing CDP session rather
than trying fragments by hand.

## Why 06 is not redundant with 02

Figure 02 is the finding and is the stronger evidence, because it was
produced under `set -x` and declares each expectation before running. But it
is a terminal, and a terminal can be made to say anything by someone who has
not read the script beside it. Figure 06 shows the same pooled table in
AWS's own interface, with both tenants' partition keys visible in one list,
and requires no trust in this repo's tooling.
