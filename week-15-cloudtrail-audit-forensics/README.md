# Week 15 — CloudTrail Organization Trail + Audit Forensics

**The story:** Weeks 11 and 12 answer *"is something wrong?"* — Security Hub and GuardDuty find the open security group and close it; Config reports whether a resource is compliant. Both describe **state**. Neither can tell you **who did it, when, from where, and what else they touched**. And once an auto-remediation has fixed the problem, the action record is the only evidence it ever happened.

This week builds the attribution layer: an organization trail, a queryable table over it, and the saved SQL to answer those questions in about thirty seconds instead of not at all.

**The motivating incident is real and from this lab.** During Week 12 the account's AWS Config recorder was deleted mid-build by an unrelated project's cleanup script. The build broke, the recorder was rebuilt — and *who deleted it* was never answerable by anyone.

---

## The roadmap topic was impossible

This was planned as *"CloudTrail Lake + Audit Automation"*. **CloudTrail Lake closed to new customers on 31 May 2026**, and this account has no event data store, so that build cannot be made. AWS recommends migrating to CloudWatch.

Worse, AWS's own org-wide Athena documentation still ends with *"in a large organization… consider using CloudTrail Lake rather than Athena"* — advice that no longer works for anyone starting today. That gap is what this week fills.

---

## Architecture

```
   Organization trail  (management events only — see cost note on copies)
   covers every account in the org
             |
             v
   ┌──────────────────────────────────────────────┐
   │ S3   AWSLogs/<org-id>/<account>/CloudTrail/   │  365-day expiry
   │      <region>/YYYY/MM/DD/                     │  (must exceed the
   └───────────────────┬──────────────────────────┘   console's own 90)
                       │  5-key partition projection, no crawler
                       v
   ┌──────────────────────────────────────────────┐
   │ Glue table  →  Athena workgroup               │  10 GB per-query
   └─────┬──────────────────────────┬─────────────┘  scan ceiling
         │                          │
   7 saved queries          audit_analyzer (daily)
   (human, forensic)                │
                                    v
                          CloudWatch metrics
                                    │
                         6 alarms — ALL STATIC
                     (these things should be zero)
                                    │
                                   SNS
```

---

## Services

| Service | Role in this build |
|---|---|
| **AWS CloudTrail** | Organization trail, management events, multi-region, log file validation |
| **AWS Organizations** | Supplies the org ID and the live account list; trusted access is a prerequisite |
| **Amazon S3** | Log destination and query source |
| **AWS Glue Data Catalog** | Table definition with partition projection — nothing crawls |
| **Amazon Athena** | SQL over the events, with a workgroup-enforced scan ceiling |
| **AWS Lambda** | Daily analyzer: Athena queries → CloudWatch metrics |
| **Amazon EventBridge** | Daily schedule |
| **Amazon CloudWatch** | Custom metrics and six static-threshold alarms |
| **Amazon SQS** | Dead letter queue — makes a broken analyzer visible |
| **Amazon SNS** | Alert delivery |

---

## The technical problem this week actually solves

AWS publishes two CloudTrail-on-Athena recipes, and neither fits an organization trail:

- The **partition-projection** example covers a *single account in a single region* — one `timestamp` key over `AWSLogs/<account-id>/CloudTrail/<region>/`
- The **organization-wide** page handles the extra path segment, but only with manual `ALTER TABLE ADD PARTITION` — one statement per account, per region, per day — then recommends CloudTrail Lake instead

So the documented options are a table that cannot see an organization, a chore AWS itself calls cumbersome, or a service you can no longer sign up for.

This build projects **five keys** instead of one:

```
AWSLogs/<org-id>/<account>/CloudTrail/<region>/<year>/<month>/<day>/
                 ^^^^^^^^^             ^^^^^^^  ^^^^^^^^^^^^^^^^^^^
                 enum                  enum     integer projections
```

**The honest trade-off:** dates project infinitely, but accounts and regions cannot — projection needs a finite set, so both are enums. An account missing from that enum has its events sitting in S3, intact, and invisible to every query. A Glue crawler would discover them automatically, at the cost of DPU-time on a schedule and lag behind new partitions.

The account list is derived from live organization state (filtered to `ACTIVE`), so the *code* self-corrects on the next apply. The *table* still does not: adding an account requires an apply.

**The region enum covers every enabled region, not just the ones in use.** One of the audit questions is *"did anything happen in a region we don't use?"* — a narrow enum makes that structurally unanswerable, returning a confident empty result.

---

## Cost

Prices as of August 2026 — verify at [aws.amazon.com/cloudtrail/pricing](https://aws.amazon.com/cloudtrail/pricing/).

| Item | Rate | This build |
|---|---|---|
| **Management events, first copy to S3** | **free** | see the caveat below |
| Additional management event copies | $2.00 / 100k | not used |
| Data events | $0.10 / 100k **from the first copy** | **not enabled** |
| S3 storage | $0.023 / GB-month | pennies at lab volume |
| Athena | $5 / TB scanned, capped at 10 GB/query | cents |
| Lambda, EventBridge, SNS, SQS, Glue catalog | — | effectively free |
| CloudWatch alarms × 6 | $0.10 / alarm / month | $0.60/month |
| **Destroyed** | | **$0** |

**No NAT gateway, no always-on compute, no anomaly-detection alarms.** Materially cheaper than Weeks 13 or 14.

### The free copy may already be taken — check before you assume $0

AWS gives you **one free copy of management events per region**. Everyone repeats that. What is
rarely said is the other half: **if a trail already exists in that region delivering management
events, yours is the second copy, and second copies bill at $2.00 per 100,000 events.**

That is the case in this account. A pre-existing trail from an unrelated project
(`ebs-savings-management-trail`) already has `IncludeManagementEvents: true` for us-east-1, so it
holds the free copy.

Measured rather than estimated — one day of that trail's own delivery:

```
253 files, 11,539 management events (partial day)
```

That extrapolates to roughly **450–600k events/month**, so a second copy in us-east-1 costs about
**$9–12/month** while the trail is up. Over a two-day build-and-destroy it is **$1–2**.

Two details soften it. Only the **management account's us-east-1** events are a second copy —
events from member accounts and other regions are first copies and remain free. And the charge
stops entirely when the trail is destroyed.

**The general lesson: before quoting "the first copy is free", run
`aws cloudtrail describe-trails` and check whether something already claimed it.**

**Why management events only:** data events bill from the *first* copy and are generated per object access — a single busy bucket can produce more in an hour than the whole org produces in management events in a month. Every question this week asks is a management event.

For contrast, the same data in CloudTrail Lake would be **$0.75/GB** (one-year) or **$2.50/GB** (seven-year, first 5 TB).

---

## Prerequisites

**Organization trails require trusted access.** There is no clean Terraform path, so this is a documented manual step — the same shape as Week 6's SCP policy-type enablement:

```bash
aws organizations enable-aws-service-access \
  --service-principal cloudtrail.amazonaws.com
```

Without it, `CreateTrail` fails with `CloudTrailAccessNotEnabledException`.

Terraform must also run in the **organization management account**.

---

## Quick Start

Deployment is via **HCP Terraform** (workspace `week-15-dev`, VCS-connected). Pushing to `main` queues a plan; apply from the HCP UI.

```bash
cd week-15-cloudtrail-audit-forensics/terraform/environments/dev
terraform init
terraform validate
```

**After apply, in order:**

```bash
# 1. Confirm the SNS subscription from the email AWS sends.
#    Alarms cannot notify until this is done.

# 2. Wait ~20 minutes. CloudTrail delivers on a 5-15 minute lag with
#    occasional longer tails.

# 3. Verify the pipeline — not optional, see below.
./scripts/verify_pipeline.sh

# 4. Generate deliberate, attributable activity for the forensic queries.
./scripts/generate_audit_activity.sh

# 5. Force an analyzer run rather than waiting for the daily schedule.
aws lambda invoke --function-name week15-audit-audit-analyzer out.json \
  && cat out.json && rm out.json
```

---

## Run `verify_pipeline.sh`. Every failure mode here is silent.

Four ways this build can be completely broken while reporting success:

1. **A projection template that does not match the delivered prefixes** returns zero rows and reports `SUCCEEDED`. The org layout has five projected keys and more ways to be subtly wrong than the single-account one AWS documents.
2. **An account missing from the projection enum** has its events in S3 and invisible to every query.
3. **A region missing from the enum** does the same — and quietly makes the unused-region question unanswerable.
4. **A bucket policy granting only the account prefix** rather than the org prefix lets the trail create successfully and silently denies every member-account delivery.

None raise anything. None are findable by re-reading the Terraform. The script compares a **real delivered S3 key** against the projection template, cross-checks which accounts are delivering against which are visible in the table, and runs a query that must return rows.

---

## Saved queries

Published into the Athena console. Source in [`athena/`](./athena).

| Query | Answers |
|---|---|
| `partition-sanity-check` | **Run first.** Is any data readable at all? |
| `who-changed-this-resource` | Who deleted or modified a named resource — *the Week 12 question* |
| `principal-activity-timeline` | Everything one user or role did in a window |
| `changes-outside-terraform` | Mutating changes that did not come from Terraform |
| `root-account-usage` | Root actions — should be zero |
| `console-login-without-mfa` | Sign-ins with no second factor — should be zero |
| `activity-in-unexpected-regions` | Mutating activity outside the regions in use — should be zero |

Three CloudTrail schema traps are already handled in the SQL:

- **`mfaauthenticated` is a STRING** (`'true'`/`'false'`) that can also be **NULL** for federated sign-ins. `<> 'true'` alone silently drops the NULL rows.
- **Role sessions leave `useridentity.username` null** — the useful name is in `sessioncontext.sessionissuer.username`. Querying only the top level misses nearly every Terraform-driven action.
- **`ConsoleLogin` events are global** and land in us-east-1 regardless of where the user is.

`changes-outside-terraform` filters on **user agent, not principal** — the same role used via the console and via Terraform is identical by principal and completely different by user agent.

---

## Alarms: all static, on purpose

| Alarm | Why static |
|---|---|
| Root account used | Zero is the correct value. An anomaly band would learn a baseline rate of root logins and stop reporting them |
| Console login without MFA | Same — every credential-theft path ends at this event |
| Activity in unexpected region | Same |
| **Trail delivered nothing** | If the trail stops, all three metrics above go to zero and read as good news. `treat_missing_data = "breaching"` |
| Analyzer DLQ not empty | The audit checks are not running |
| Analyzer not running | Catches a disabled schedule, where nothing fails because nothing runs |

This is deliberately the opposite of Week 14, which used anomaly detection for traffic volume — a metric whose normal is genuinely unknown and diurnal. **A metric whose correct value is a fact wants a fixed threshold.** It is also 30× cheaper ($0.10 vs $3.00/alarm/month).

Side effect: nothing creates an implicit anomaly detector, so teardown leaves no orphan — unlike Week 14.

---

## Security patterns

- **Management events only** — no data events, so no object-level access logging and no per-object cost
- **Log file validation on** — signed digests let you later prove a log was not altered after delivery
- **Bucket policy scoped by `aws:SourceArn`** to this specific trail, against the confused-deputy case
- **Bucket policy denies non-TLS access**; all public access blocked, `BucketOwnerEnforced`, SSE-S3
- **Least-privilege IAM** — the analyzer's Athena permissions are scoped to the one workgroup carrying the scan ceiling; a broad `athena:*` would let it bypass the guardrail the design depends on. `PutMetricData` supports no resource-level permission, so it is constrained by a namespace condition
- **Spend as a control** — the 10 GB per-query ceiling is enforced at workgroup level, so a forensic query written under pressure cannot become an unbounded bill

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `CloudTrailAccessNotEnabledException` on apply | Trusted access not enabled | Run the `enable-aws-service-access` command above |
| Trail creates, no member-account logs | Bucket policy grants only the account prefix | It must also grant `AWSLogs/<org-id>/*` |
| Query succeeds, zero rows, objects in S3 | Projection template mismatch | Compare `terraform output partition_location_template` against a real key |
| One account missing from results | Account absent from the projection enum | Check `terraform output projected_accounts` |
| Unused-region query always empty | Region enum too narrow, or trail not multi-region | Both must cover the regions being asked about |
| MFA query returns nothing | `mfaauthenticated` compared as a boolean, or NULLs dropped | It is a string and can be NULL |
| Query cancelled, `SCAN_BYTES_EXCEEDED` | Scan ceiling fired | Working as intended — add or tighten the partition filter |
| `aws logs` CLI errors on a `/aws/...` argument | Git Bash rewrites leading-slash arguments | Prefix with `MSYS_NO_PATHCONV=1` |

---

## Teardown

Queue a destroy from the HCP UI (Workspace → Settings → Destruction and Deletion → Queue destroy plan), or via the API with `is-destroy: true`. A VCS-connected workspace blocks CLI `terraform destroy`, not an HCP-queued destroy.

```bash
./scripts/cleanup.sh
```

**The organization trail is the one that matters.** Left behind, it keeps writing every management event from every account in the organization into a bucket indefinitely — and because the first copy is free, there is no sharp cost signal to make you notice.

Trusted access is deliberately left enabled: it is an organization-level setting, it was a manual prerequisite, and other services may rely on it. Removing it is a separate decision.
