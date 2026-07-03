# Week 08 — S3 Intelligent Storage Platform

**The story:** S3 costs grow invisibly — objects uploaded once, never moved, billed at Standard rates for years. This platform automates tiering with S3 Intelligent-Tiering and Lifecycle Policies, then delivers a daily email showing exactly how much the automation is saving versus doing nothing.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                    S3 Intelligent Storage Platform                   │
│                                                                      │
│  S3 Bucket (versioned, encrypted)                                   │
│  ├── Intelligent-Tiering  →  Frequent (0d) → Infrequent (30d)      │
│  │                            → Archive Instant (90d)               │
│  │                            → Deep Archive (180d)                 │
│  ├── Lifecycle: logs/ prefix                                        │
│  │   Standard → IA (30d) → Glacier IR (90d) → Delete (365d)        │
│  ├── Lifecycle: AbortIncompleteMultipartUpload (7d)                 │
│  └── Lifecycle: NoncurrentVersionExpiration (30d)                   │
│                                                                      │
│  S3 ObjectCreated event                                              │
│       │                                                              │
│       ▼                                                              │
│  SQS Queue ──► Lambda: object_tagger                                │
│                └── Tags objects (content-type, upload-date)         │
│                                                                      │
│  EventBridge (daily) ──► Lambda: storage_cost_reporter              │
│                          ├── Queries CloudWatch storage metrics     │
│                          ├── Calculates actual vs. Standard cost    │
│                          └── SNS ──► Email report                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Services

| Service | Role |
|---|---|
| S3 + Intelligent-Tiering | Auto-moves objects between access tiers based on actual usage |
| S3 Lifecycle Policies | Deterministic transitions for `logs/` prefix; cleans up orphaned multipart uploads and old versions |
| Lambda: object_tagger | Tags every new object with content-type and upload-date |
| Lambda: storage_cost_reporter | Daily savings report: actual tiered cost vs. all-Standard cost |
| SQS | Buffers S3 ObjectCreated events to object_tagger (production-safe pattern) |
| EventBridge | Daily cron trigger for storage_cost_reporter |
| SNS + Email | Delivers daily report to your inbox |
| CloudWatch Alarms | Alerts when object_tagger failures land in the DLQ |

---

## Key Design Decisions

**Intelligent-Tiering + Lifecycle on the same bucket:** IT applies to the entire bucket (objects with unpredictable access patterns). The `logs/` lifecycle rule uses a prefix filter and deterministic transitions for data where access patterns are known. They coexist without conflict.

**SQS between S3 and Lambda:** Direct S3 → Lambda triggers can drop events under high object creation rates. S3 → SQS → Lambda is the production-safe pattern; SQS provides buffering and retry with DLQ visibility.

**Circular dependency resolved in locals:** `s3-storage` needs the SQS queue ARN (from `cost-automation`), and `cost-automation` needs the bucket ARN (from `s3-storage`). Both are computed deterministically in `environments/dev/main.tf` locals using the account ID — no cross-module output dependency needed.

**Versioning + NoncurrentVersionExpiration:** Versioning is enabled for object recovery. Without `NoncurrentVersionExpiration`, every overwrite retains the previous version indefinitely — a silent storage cost that compounds with every write.

**AbortIncompleteMultipartUpload:** Large file uploads that fail mid-way leave orphaned parts billed at Standard rates indefinitely. The 7-day abort rule eliminates this.

---

## Quick Start

### Prerequisites

- AWS CLI configured with appropriate permissions
- Terraform >= 1.10.0
- `SNS_EMAIL` and `AWS_ACCOUNT_ID` set as GitHub Actions secrets

### Local Deploy

```bash
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set sns_email to your address
terraform init
terraform plan
terraform apply
```

After deploy, **confirm the SNS email subscription** from the AWS notification in your inbox — the daily report will not deliver until you confirm.

### GitHub Actions Deploy

| Workflow | Trigger | Action |
|---|---|---|
| `week-08-deploy.yml` | Manual (`workflow_dispatch`) | `terraform apply` |
| `week-08-destroy.yml` | Manual (`workflow_dispatch`) | Empty bucket, then `terraform destroy` |

**Required GitHub Actions secrets:**

| Secret | Value |
|---|---|
| `AWS_ACCOUNT_ID` | Your AWS account ID |
| `SNS_EMAIL` | Email address for daily reports |

---

## Testing After Deploy

**Upload test objects:**
```bash
BUCKET=$(cd terraform/environments/dev && terraform output -raw bucket_name)

# Create a logs/ object to trigger lifecycle rules
echo "test log entry" | aws s3 cp - s3://$BUCKET/logs/app/2026-06-30.log

# Create a data/ object
echo '{"event":"test"}' | aws s3 cp - s3://$BUCKET/data/events/test.json

# Verify object_tagger applied tags
aws s3api get-object-tagging --bucket $BUCKET --key logs/app/2026-06-30.log
```

**Invoke the cost reporter manually** (CloudWatch metrics take 24h to appear; first run may show empty data):
```bash
REPORTER=$(cd terraform/environments/dev && terraform output -raw storage_reporter_function_name)
aws lambda invoke --function-name $REPORTER out.json && cat out.json && rm out.json
```

**Check object_tagger DLQ:**
```bash
aws sqs get-queue-attributes \
  --queue-url $(cd terraform/environments/dev && terraform output -raw sqs_queue_url | sed 's/object-events/object-events-dlq/') \
  --attribute-names ApproximateNumberOfMessages
```

---

## Cost

All prices us-east-1, verified 2026-06-30 — verify current rates at [aws.amazon.com/s3/pricing](https://aws.amazon.com/s3/pricing/).

| Resource | Estimated Monthly Cost |
|---|---|
| S3 Standard storage | $0.023/GB |
| S3 Standard-IA (after 30d) | $0.0125/GB |
| S3 Glacier IR (after 90d) | $0.004/GB |
| IT monitoring fee | $0.0025/1,000 objects |
| Lambda (2 functions, low invocations) | < $0.01 |
| SQS (pay per request) | < $0.01 |
| SNS (1 email/day) | < $0.01 |
| **Destroyed** | **$0** |

**Typical savings:** 67% reduction in storage costs for buckets with mixed hot/cold data, per AWS data across thousands of customer buckets.

---

## Security

| Control | Implementation |
|---|---|
| Encryption at rest | AES-256 (SSE-S3) with bucket key enabled |
| Public access | Blocked at all four settings |
| IAM least privilege | object_tagger scoped to one bucket; reporter scoped to CloudWatch + SNS only |
| OIDC authentication | No static AWS credentials in GitHub Actions |
| SQS source condition | Queue policy restricts `SendMessage` to the specific bucket ARN only |

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| No report email after deploy | SNS subscription not confirmed | Check inbox for AWS confirmation email and click confirm |
| Reporter shows no data | CloudWatch S3 metrics have 24h delay | Wait 24h after uploading objects, then invoke reporter again |
| object_tagger DLQ has messages | S3 event format mismatch or S3 permissions issue | Check CloudWatch logs for the object_tagger Lambda |
| `terraform destroy` fails on bucket | Bucket not empty (versioned objects remain) | Run `scripts/cleanup.sh` which empties versions before destroy |
| Lifecycle not transitioning objects | Objects in `logs/` prefix are < 30 days old | Lifecycle evaluates daily; transitions happen at the configured age |

---

## Blog Post

[Week 08 — S3 Intelligent Storage Platform](https://jayanthkatta.com/blog/week-8-s3-intelligent-storage-platform/)
