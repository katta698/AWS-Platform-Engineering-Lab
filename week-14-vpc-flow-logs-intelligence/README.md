# Week 14 — VPC Flow Logs + Network Intelligence

**The story:** flow logs get switched on for a compliance checkbox, quietly write tens of gigabytes a month into a bucket nobody has permission to read, and are never queried again — until an incident, when the answer is technically sitting in S3 and unreachable in under a day. This week builds the layer that makes them answer questions: Parquet on S3, a Glue table that needs no crawler, an Athena workgroup that cannot run away with the bill, saved queries an on-call engineer can actually use, and an hourly analyzer that turns traffic into metrics with anomaly detection on top.

The single highest-leverage decision in here is one configuration field. Flow logs to **S3 cost $0.25/GB**; the same logs to **CloudWatch Logs cost $0.50/GB** — and Parquet, which is what makes querying affordable, is only offered on the S3 path.

---

## Architecture

```
                      ┌─────────────────────────────────────────┐
                      │  VPC 10.14.0.0/16                       │
                      │                                         │
   internet ──scan──▶ │  [exposed]  SG with NO ingress rules    │
                      │      └─▶ every packet REJECTed          │
                      │                                         │
                      │  [generator] ──▶ NAT GW ──▶ internet    │  traffic_path 2  $0.045/GB
                      │       └────────▶ S3 gateway endpoint    │  traffic_path 7  FREE
                      └───────────────────┬─────────────────────┘
                                          │  flow logs: Parquet, hive-partitioned,
                                          │  record version 11 (tags + next-hop)
                                          ▼
                              ┌───────────────────────┐
                              │  S3  (30-day expiry)  │
                              └───────────┬───────────┘
                                          │  partition projection — no crawler
                                          ▼
                              ┌───────────────────────┐
                              │  Glue table           │
                              │  Athena workgroup     │  10 GB per-query scan ceiling
                              └─────┬───────────┬─────┘
                                    │           │
                    7 saved queries │           │ hourly analyzer Lambda
                    (humans, ad hoc)│           ▼
                                    │   CloudWatch metrics
                                    │           │
                                    │     ┌─────┴──────┐
                                    │     │  anomaly   │ volume, NAT egress
                                    │     │  static    │ port scans, DLQ, silence
                                    │     └─────┬──────┘
                                    │           ▼
                                    │          SNS ──▶ email
```

---

## Services

| Service | Role in this build |
|---|---|
| **VPC Flow Logs** | Capture, at VPC scope, record version 11 with a custom 32-field format |
| **Amazon S3** | Destination and query source. Parquet, hive prefixes, hourly partitions |
| **AWS Glue Data Catalog** | Table definition with partition projection — nothing crawls, nothing schedules |
| **Amazon Athena** | Query engine, with a workgroup-enforced per-query scan ceiling |
| **AWS Lambda** | Hourly analyzer: Athena queries → CloudWatch custom metrics |
| **Amazon EventBridge** | Hourly schedule |
| **Amazon CloudWatch** | Custom metrics, anomaly detection bands, static alarms |
| **Amazon SQS** | Dead letter queue — makes a broken analyzer visible |
| **Amazon SNS** | Alert delivery |
| **NAT Gateway / VPC Endpoint** | The two egress routes whose cost difference the whole thing measures |

---

## Why record version 11 matters

Most published examples of this table stop at version 5. The fields this build depends on are newer:

| Field | Version | Why it is here |
|---|---|---|
| `pkt_srcaddr` | 3 | Behind NAT, `srcaddr` is the gateway. Reading only `srcaddr` gives an answer that looks fine and is wrong |
| `traffic_path` | 5 | `2` = NAT/IGW (billed), `7` = gateway endpoint (free). This is what makes flow logs a cost tool |
| `reject_reason` | 8 | Distinguishes a Block-Public-Access drop from an ordinary security group denial |
| `interface_type`, `next_hop_*` | 11 | Which intermediate resource actually handled the flow, stated rather than inferred from route tables |
| `instance_tag` | 11 | The instance's own tag **value**, embedded in the record — turns cost attribution from a stale inventory join into a `GROUP BY` |

`instance_tag` requires **both** `tag_field_specification` on the flow log **and** `ec2:DescribeTags` on the delivery role. Miss either and the column fills with `-`. There is no error.

---

## Quick Start

Deployment is through **HCP Terraform** (workspace `week-14-dev`, VCS-connected). Pushing to `main` queues a plan; apply from the HCP UI.

```bash
cd week-14-vpc-flow-logs-intelligence/terraform/environments/dev
terraform init
terraform validate
```

The workspace needs two environment variables for AWS OIDC credentials — `TFC_AWS_PROVIDER_AUTH=true` and `TFC_AWS_RUN_ROLE_ARN`. `alert_email` arrives from the org-wide `shared-alert-email` variable set.

**After apply, in order:**

```bash
# 1. Confirm the SNS subscription from the email AWS sends. Alarms cannot
#    notify until this is done.

# 2. Wait ~15 minutes. Flow logs reach S3 in about 10, written in 5-minute
#    batches. Querying sooner shows nothing and looks like a broken pipeline.

# 3. Verify the pipeline end to end — this is not optional, see below.
./scripts/verify_pipeline.sh

# 4. Generate a deliberate, identifiable signal against your own instance.
./scripts/generate_signal.sh "$(terraform output -raw exposed_instance_public_ip)"

# 5. Force an analyzer run rather than waiting for the hourly schedule.
aws lambda invoke --function-name week14-flowlogs-flow-analyzer out.json \
  && cat out.json && rm out.json
```

---

## Run `verify_pipeline.sh`. Every failure mode here is silent.

This build has three ways to be completely broken while reporting success:

1. **A partition projection template that does not match the real S3 prefixes** returns zero rows and reports `SUCCEEDED`. A dashboard on top shows a flat, healthy-looking zero line indefinitely.
2. **A delivery role missing `ec2:DescribeTags`** produces a column of `-` instead of tag values. No error.
3. **A `log_format` whose field order disagrees with the Glue schema** returns values under the wrong column names — all of them plausible numbers.

None of these raise anything. None are findable by re-reading the Terraform. `verify_pipeline.sh` checks a real delivered S3 key against the projection template, confirms the subscription is `ACTIVE` with no delivery error, runs a query that must return rows, and warns if the tag column has collapsed to a single value.

The format-order risk is handled structurally: the field list is declared **once** in `terraform/environments/dev/main.tf` and generates both the flow log format string and the Glue columns, so the two cannot disagree.

---

## Saved queries

Published into the Athena console as named queries. Source in [`athena/`](./athena).

| Query | Answers |
|---|---|
| `partition-sanity-check` | **Run first.** Is any data readable at all, and are the tag fields resolving? |
| `top-talkers` | Which source/destination pairs moved the most bytes |
| `rejected-traffic` | Rejected flows clustered by source — repetition and spread, not single events |
| `port-scan-candidates` | Sources rejected across 20+ distinct ports on one target |
| `nat-cost-attribution` | NAT egress bytes and projected cost, grouped by owning team |
| `traffic-path-contrast` | Egress by route taken: billed NAT paths against free endpoint paths |
| `next-hop-path-trace` | Which intermediate resource handled each flow |

Every query filters on partitions. Athena bills on data **scanned**, so a missing partition filter is not a slow query — it is an expensive one.

---

## Alarms: anomaly detection *and* static thresholds

The split is deliberate, and using anomaly detection for everything would cost 30× more and detect less.

| Alarm | Type | Reasoning |
|---|---|---|
| Traffic volume outside band | Anomaly | Nobody knows a VPC's normal byte volume at deploy time, and it varies by hour. A static threshold either alarms constantly or never fires |
| NAT egress above band | Anomaly | Same, and this is the billed portion — total traffic can be flat while the charged share climbs |
| Port scan detected | **Static** | Zero is the correct value. Anomaly detection would learn a baseline rate of port scanning and stop reporting it |
| Analyzer DLQ not empty | **Static** | The analyzer failing is its own incident |
| Analyzer not running for 3h | **Static** | Catches a disabled schedule, where nothing fails because nothing runs. `treat_missing_data = breaching` — a missing datapoint *is* the failure |

Anomaly-detection alarms bill **three** metrics each (value, upper band, lower band) at $3.00/month; a static alarm is $0.10.

---

## Cost

Prices as of August 2026 — verify at [aws.amazon.com/vpc/pricing](https://aws.amazon.com/vpc/pricing/) and [aws.amazon.com/cloudwatch/pricing](https://aws.amazon.com/cloudwatch/pricing/).

| Item | Rate | 48-hour build-test-destroy |
|---|---|---|
| NAT Gateway | $0.045/hr + $0.045/GB processed | ~$2.16 |
| 2 × t4g.nano | $0.0042/hr each | ~$0.40 |
| Flow log ingest to S3 | $0.25/GB (vended logs) | < $0.10 at lab volume |
| S3 storage | $0.023/GB-month | cents |
| Athena | $5/TB scanned, 10 MB minimum/query | cents |
| Anomaly alarms × 2 | $3.00/month each, prorated hourly | ~$0.02 |
| Static alarms × 3 | $0.10/month each | negligible |
| Lambda, EventBridge, SNS, SQS, Glue catalog | — | effectively free at this volume |
| **Total** | | **≈ $3** |
| **Destroyed** | | **$0** |

**Left running: ~$33/month, roughly 75% of it NAT Gateway.** The NAT gateway bills whether or not a single packet flows and produces no usage signal to remind you it exists. On this build, forgetting is the risk — not the rate.

Cost controls that are actually in the code, not just advice:

- **S3 lifecycle expiry at 30 days**, plus noncurrent-version expiry — versioning is on, so expiry alone would only create delete markers while the billed bytes stayed
- **Incomplete multipart upload abort at 7 days** — invisible in the console object list, billed anyway
- **Athena results expire at 7 days**
- **`bytes_scanned_cutoff_per_query` = 10 GB**, enforced at workgroup level so no client can opt out

---

## Security patterns

- **No SSH, no inbound ports, no key pairs.** Instance access is SSM Session Manager only
- **IMDSv2 required** on both instances
- **The exposed instance's security group has no ingress rules at all.** It is internet-*reachable* but nothing can connect — the denials are what produce the REJECT records this week analyses
- **Encrypted root volumes**, S3 SSE-S3 with bucket keys, SQS SSE
- **Bucket policy denies non-TLS access** and scopes log delivery with both `aws:SourceAccount` and `aws:SourceArn` conditions against the confused-deputy case
- **All public access blocked**, `BucketOwnerEnforced` ownership
- **Least-privilege IAM throughout**: the analyzer's Athena permissions are scoped to the one workgroup that carries the scan ceiling, and `PutMetricData` is constrained by a namespace condition since it supports no resource-level permission

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Query succeeds, zero rows, objects visible in S3 | Projection template does not match delivered prefixes | Compare `terraform output partition_location_template` against a real key from `aws s3 ls s3://<bucket>/AWSLogs/ --recursive \| tail -3` |
| `instance_tag` column is all `-` | Delivery role missing `ec2:DescribeTags`, or `tag_field_specification` absent | Both are required. Check the flow_logs module |
| No objects in the bucket at all | Delivery lag, or bucket policy rejecting writes | Wait 15 min; then check `DeliverLogsErrorMessage` in `aws ec2 describe-flow-logs` |
| Values look wrong but plausible | `log_format` order disagrees with Glue column order | Should be structurally impossible — both derive from one list. If it happens, that list was edited without re-applying |
| Query cancelled, `SCAN_BYTES_EXCEEDED` | Scan ceiling fired | Working as intended. Add or tighten the partition filter |
| Analyzer succeeds but publishes nothing | Query returned no rows | Check the analyzer log group; run `partition-sanity-check` |
| Alarms never notify | SNS email subscription unconfirmed | Confirm from the email AWS sent at apply |
| `aws logs` CLI errors on a `/aws/...` argument | Git Bash rewrites leading-slash arguments to Windows paths | Prefix with `MSYS_NO_PATHCONV=1` |

---

## Teardown

Queue a destroy from the HCP UI (Workspace → Settings → Destruction and Deletion → Queue destroy plan), or via the API with `is-destroy: true`. A VCS-connected workspace blocks CLI `terraform destroy`, not an HCP-queued destroy.

Then verify — the script reports what survived and fails loudly if a check could not run:

```bash
./scripts/cleanup.sh
```

It separately checks the NAT gateway, the Elastic IP (billed hourly on its own once detached), the S3 bucket, and CloudWatch **anomaly detectors** — which are a different API from alarms and survive alarm deletion.
