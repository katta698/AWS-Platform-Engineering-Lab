# Week 04 — Glue Fleet Intelligence Platform

**The story:** An ops engineer submits a ServiceNow ticket: "Run fleet intelligence report" → SSM inventory and patch data is automatically synced to S3, crawled by Glue, transformed by an ETL job, and made queryable via Athena — all in under 10 minutes. No manual exports. No scripts. Just SQL.

---

## What It Builds

- **SSM Resource Data Sync** — continuously exports EC2 inventory + patch compliance data to S3 (raw zone)
- **Glue Crawler** — auto-discovers schema from SSM raw data, registers tables in Glue Data Catalog
- **Glue ETL Job** (PySpark) — transforms raw JSON → curated Parquet, partitioned by date + account
- **Athena** — SQL queries across entire fleet; patch compliance, missing patches, OS inventory
- **Step Functions** — orchestrates the full pipeline (trigger → crawl → ETL → notify)
- **Lambda** — ServiceNow webhook receiver, Glue pipeline trigger, status updater
- **API Gateway** — HTTPS endpoint for ServiceNow webhook
- **S3** — raw zone (SSM export) + curated zone (Parquet) + Athena results

---

## Architecture

```
ServiceNow Ticket (RITM)
        ↓
API Gateway (HTTPS + HMAC)
        ↓
Lambda: webhook_receiver
        ↓
Step Functions State Machine
        ↓
  ┌─────────────────────────────────┐
  │ 1. Enable SSM Resource Data Sync│
  │ 2. Wait for S3 data (60s poll)  │
  │ 3. Start Glue Crawler           │
  │ 4. Poll crawler until READY     │
  │ 5. Start Glue ETL Job           │
  │ 6. Poll job until SUCCEEDED     │
  │ 7. Update ServiceNow: CLOSED    │
  └─────────────────────────────────┘
        ↓
S3 Raw:     s3://jay-fleet-intelligence/raw/ssm/
S3 Curated: s3://jay-fleet-intelligence/curated/fleet/
        ↓
Athena (query curated zone)
```

---

## What You Can Query

Once the pipeline runs, Athena gives you SQL over your entire EC2 fleet:

```sql
-- Patch compliance summary by environment
SELECT environment, compliance_status, COUNT(*) as instance_count
FROM fleet_curated.patch_compliance
GROUP BY environment, compliance_status;

-- Instances missing critical patches
SELECT instance_id, instance_name, missing_patch_count, last_seen
FROM fleet_curated.patch_compliance
WHERE compliance_status = 'NON_COMPLIANT'
  AND severity = 'Critical'
ORDER BY missing_patch_count DESC;

-- Instances not patched in 30+ days
SELECT instance_id, instance_name, last_patch_time, platform_name
FROM fleet_curated.patch_compliance
WHERE last_patch_time < NOW() - INTERVAL '30' DAY;

-- OS version inventory across fleet
SELECT platform_name, platform_version, COUNT(*) as count
FROM fleet_curated.inventory
GROUP BY platform_name, platform_version
ORDER BY count DESC;

-- Software installed on all instances
SELECT instance_id, name, version
FROM fleet_curated.applications
WHERE name LIKE '%python%';
```

---

## Key AWS Services

| Service | Role |
|---------|------|
| SSM Resource Data Sync | Continuously exports inventory + patch data to S3 |
| AWS Glue Crawler | Auto-discovers schema from raw SSM JSON |
| AWS Glue Data Catalog | Central metadata store for all fleet tables |
| AWS Glue ETL (PySpark) | Transforms raw → curated Parquet |
| Amazon Athena | SQL queries over S3 curated data |
| S3 | Raw + curated data lake zones |
| Step Functions | Pipeline orchestration |
| Lambda | Webhook receiver, Glue trigger, status updater |
| API Gateway | ServiceNow webhook endpoint |
| IAM | Least-privilege roles for Glue, Athena, SSM |

---

## Connection to Week 03

Week 03 automates patching. Week 04 answers: **did it work?**

- Week 03 SSM Patch Manager runs patches → compliance state written to SSM
- Week 04 Glue pipeline reads that compliance state → queryable SQL in Athena
- Together: automated patching + automated visibility = complete fleet management platform

---

## Terraform Resources (~55 resources)

```
S3 buckets (raw + curated + athena results) with versioning + lifecycle
Glue Catalog database + crawler + ETL job
Athena workgroup + named queries
Step Functions state machine
3x Lambda functions + IAM roles
API Gateway REST API
SSM Resource Data Sync configuration
CloudWatch log groups
```

---

## Prerequisites

- Week 03 deployed (EC2 fleet with SSM agents registered)
- S3 state bucket: `jay-terraformstate-bucket`
- GitHub OIDC role: `github-actions-dev-deploy-role`
- Terraform >= 1.10

---

## Deploy Steps

### Option A — One command (recommended)

Run from the `week-04-glue-fleet-intelligence/` folder:

```bash
bash scripts/deploy.sh
```

This does everything in sequence:
1. Packages all 3 Lambda zip files
2. Tries to upload the Glue ETL script (skips gracefully if bucket doesn't exist yet)
3. `terraform init` + `terraform apply`
4. Uploads the Glue ETL script again (bucket now exists)

### Option B — Manual steps

```bash
# 1. Package Lambda functions
bash scripts/build_zips.sh

# 2. Deploy infrastructure
cd terraform/environments/dev
terraform init
terraform apply

# 3. Upload Glue ETL script (after bucket exists)
aws s3 cp glue/scripts/fleet_etl.py \
  s3://jay-fleet-intelligence-raw-dev/scripts/fleet_etl.py
```

### After deploy (both options)

```bash
# 4. Submit test webhook — see COMMANDS.md section 5 for the full curl command
# 5. Monitor in Step Functions console
# 6. Query fleet data in Athena
```

> 📸 **Screenshot:** `terraform apply` complete — show resources created count
> Save as: `blog/screenshots/01-terraform-apply.png`

> 📸 **Screenshot:** GitHub Actions deploy workflow — all steps green
> Save as: `blog/screenshots/02-github-actions.png`

> 📸 **Screenshot:** S3 Console — all 3 buckets (raw, curated, athena-results)
> Save as: `blog/screenshots/03-s3-buckets.png`

> 📸 **Screenshot:** SSM Console → Fleet Manager → Resource Data Sync configured
> Save as: `blog/screenshots/04-ssm-data-sync.png`

> 📸 **Screenshot:** S3 raw bucket → ssm/ prefix with AccountID folders
> Save as: `blog/screenshots/05-s3-raw-ssm-data.png`

> 📸 **Screenshot:** Glue Console → Data Catalog → Database created
> Save as: `blog/screenshots/06-glue-data-catalog.png`

> 📸 **Screenshot:** Glue Crawler run complete — tables discovered count
> Save as: `blog/screenshots/07-glue-crawler-run.png`

> 📸 **Screenshot:** Glue Data Catalog → Tables (patch_compliance, inventory, applications)
> Save as: `blog/screenshots/08-glue-tables.png`

> 📸 **Screenshot:** Glue ETL job details page
> Save as: `blog/screenshots/09-glue-etl-job.png`

> 📸 **Screenshot:** Glue ETL job run — SUCCEEDED with duration
> Save as: `blog/screenshots/10-glue-etl-run.png`

> 📸 **Screenshot:** S3 curated bucket → fleet/ Parquet files
> Save as: `blog/screenshots/11-s3-curated-data.png`

> 📸 **Screenshot:** Step Functions state machine visual graph
> Save as: `blog/screenshots/12-step-functions.png`

> 📸 **Screenshot:** Step Functions execution — SUCCEEDED with timeline
> Save as: `blog/screenshots/13-step-functions-execution.png`

> 📸 **Screenshot:** ServiceNow RITM ticket — open state
> Save as: `blog/screenshots/14-servicenow-ticket.png`

> 📸 **Screenshot:** ServiceNow RITM ticket — Closed Complete with Athena URL in notes
> Save as: `blog/screenshots/15-servicenow-closed.png`

> 📸 **Screenshot:** Athena workgroup configuration page
> Save as: `blog/screenshots/16-athena-workgroup.png`

> 📸 **Screenshot:** Athena Query Editor — patch compliance query + results
> Save as: `blog/screenshots/17-athena-patch-compliance.png`

> 📸 **Screenshot:** Athena Query Editor — OS inventory query + results
> Save as: `blog/screenshots/18-athena-os-inventory.png`

> 📸 **Screenshot:** API Gateway Console — POST /webhook endpoint
> Save as: `blog/screenshots/19-api-gateway.png`

---

## Cost If Left Running

| Resource | Cost |
|----------|------|
| Glue crawler (per run) | ~$0.44 |
| Glue ETL job (per run) | ~$0.88 |
| Athena (per query) | ~$0.005 per GB scanned |
| S3 storage | ~$0.023/GB/month |
| **Destroyed** | **$0** |

---

## Blog

Blog post: `blog/week-04-blog.html` — ready for screenshots then publish.

Target URL: https://blog.jayanthkatta.com/2026/06/week-4-sql-over-your-fleet.html
