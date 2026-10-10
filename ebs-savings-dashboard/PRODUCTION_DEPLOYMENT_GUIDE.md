# EBS Savings Dashboard — Production Deployment Guide

**Verified against live AWS and Terraform documentation: June 30, 2026.**
Every section in this document was cross-checked against official docs before being written.
Source links are included at the end of each section so you can verify independently.

---

## Table of Contents

1. [Architecture — What Gets Built and Why](#1-architecture)
2. [Before You Start — Pre-Requisites Checklist](#2-pre-requisites)
3. [Step 1 — Terraform State Backend (S3, No DynamoDB)](#3-step-1--terraform-state-backend)
4. [Step 2 — KMS Encryption Keys](#4-step-2--kms-encryption-keys)
5. [Step 3 — AWS Data Exports (CUR 2.0)](#5-step-3--aws-data-exports-cur-20)
6. [Step 4 — Glue Crawler and Athena](#6-step-4--glue-crawler-and-athena)
7. [Step 5 — Lambda Function](#7-step-5--lambda-function)
8. [Step 6 — API Gateway](#8-step-6--api-gateway)
9. [Step 7 — Cognito Authentication](#9-step-7--cognito-authentication)
10. [Step 8 — CloudFront, WAF, and S3 Frontend](#10-step-8--cloudfront-waf-and-s3-frontend)
11. [Step 9 — Cross-Account IAM Role (HCP Terraform, 400+ Accounts)](#11-step-9--cross-account-iam-role)
12. [Step 10 — HCP Terraform OIDC Dynamic Credentials](#12-step-10--hcp-terraform-oidc-dynamic-credentials)
13. [Step 11 — Build and Deploy the React App](#13-step-11--build-and-deploy-the-react-app)
14. [Step 12 — DNS and Custom Domain](#14-step-12--dns-and-custom-domain)
15. [Terraform Variables Reference](#15-terraform-variables-reference)
16. [Cost Estimate](#16-cost-estimate)
17. [Personal Test vs Production — Side by Side](#17-personal-test-vs-production)
18. [Troubleshooting](#18-troubleshooting)

---

## 1. Architecture

```
AWS Organization — Management Account
│
│  AWS Billing writes CUR 2.0 Parquet files daily (automatic, you do not trigger it)
│       ↓
│  S3 Bucket (CUR data)                   ← KMS customer-managed key (CMK)
│       ↓
│  AWS Glue Crawler (runs daily, 6am UTC)  ← reads Parquet, registers table in Glue catalog
│       ↓
│  Amazon Athena Workgroup                 ← serverless SQL, engine v3, 10 GB scan cap
│  S3 Bucket (query results)              ← KMS CMK, 3-day auto-delete lifecycle
│       ↓
│  AWS Lambda (Python 3.12)               ← runs SQL, reads results, calls EC2 per account
│  SQS DLQ + CloudWatch Logs             ← observability
│       ↓
│  API Gateway HTTP API v2                ← HTTPS, Cognito JWT authorizer, throttled
│       ↓
│  Amazon CloudFront + AWS WAF            ← CDN, DDoS protection, HTTPS enforced
│  S3 Bucket (React app files)           ← private, OAC-only access
│
Member Accounts (400+)
│  IAM Role: EBSDashboardReadRole
│  └── ec2:Describe* (read-only, no write access)
│      Lambda assumes this role via STS to pull volume inventory per account
```

### Data flow in plain English

| Layer | What it does | Who triggers it |
|---|---|---|
| AWS Billing | Writes daily Parquet files to your CUR S3 bucket | AWS (automatic) |
| Glue Crawler | Reads those files, updates the Athena table schema | Daily schedule (or manual) |
| Athena | Runs SQL to aggregate EBS spend by month/account/region/type | Lambda |
| Lambda | Runs the SQL, waits for results, calls EC2 across accounts, formats JSON | API Gateway |
| API Gateway | Exposes a single HTTPS endpoint the dashboard calls | React frontend |
| CloudFront + WAF | Serves the React app, proxies /api/* to API GW, blocks attacks | Browser |
| React app | Renders the charts, tables, and KPIs | Browser |

---

## 2. Pre-Requisites

Work through this checklist before running any Terraform.

### 2a. AWS Account and Permissions
- You must be working in the **Management Account** (the payer — the one that sees all billing)
- You need `AdministratorAccess` or a custom role with permissions to create IAM, S3, Lambda,
  Athena, Glue, API Gateway, CloudFront, WAF, KMS, and CloudWatch resources
- AWS Organizations must be enabled (needed for cross-account role trust scoping)

### 2b. Check if CUR 2.0 Already Exists
CUR is a billing feature enabled once. **Do not create a duplicate.**

```bash
# Check for existing Data Exports (CUR 2.0)
aws bcm-data-exports list-exports --region us-east-1

# Also check for legacy CUR (older format)
aws cur describe-report-definitions --region us-east-1
```

What to look for in the output:
- `S3Bucket` — the bucket name the dashboard will read from
- `S3Prefix` — the folder path within that bucket
- `Format` — must be `Parquet` (not CSV/GZIP). If it is CSV, you need a new export.
- `TableConfigurations.CUR2_0` or similar — confirms it is CUR 2.0 not legacy

If CUR 2.0 already exists: **skip Step 3's Terraform module** and use the existing bucket.
If only legacy CUR exists: create a new CUR 2.0 export (they can coexist).
If nothing exists: run Step 3 to create it.

### 2c. Request 36-Month CUR Backfill
CUR data starts accumulating from the day you enable it. AWS can backfill up to 36 months
of historical data on request — this is critical for showing historical cleanup savings.

After enabling CUR 2.0, open a support case:
```
AWS Support → Create case → Account and billing → Data Exports
Subject: "CUR 2.0 backfill request"
Body: Account ID, export name, number of months to backfill (up to 36)
```
Backfill takes 24-72 hours. Do this immediately after enabling — do not wait.

### 2d. Required Tools
```bash
terraform --version   # must be >= 1.10.0 (for S3-native locking)
aws --version         # must be >= 2.x
node --version        # must be >= 18
npm --version         # must be >= 9
```

### 2e. HCP Terraform Workspace
- You need an HCP Terraform organization and a workspace for this deployment
- **Check your tier:** Terraform Stacks (the recommended cross-account approach in Step 9)
  requires HCP Terraform **Plus** tier. If you are on Free or Standard, use the
  `generate_providers.py` fallback also documented in Step 9.
- Ask your platform team: "What tier is our HCP Terraform org on?"

### 2f. Custom Domain and ACM Certificate (recommended)
A domain like `ebs-savings.internal.yourcompany.com` makes the dashboard shareable.
You need an ACM certificate in **us-east-1** (CloudFront requires us-east-1 regardless
of where your other resources live). See Step 12.

### 2g. Cognito User Pool
Check if your org already has one:
```bash
aws cognito-idp list-user-pools --max-results 20
```
If yes, get the User Pool ID and App Client ID — you will pass them as Terraform variables.
If no, Step 7 walks through creating one.

---

## 3. Step 1 — Terraform State Backend

### Why S3, not DynamoDB

As of Terraform 1.10, the S3 backend supports **native state locking** using S3 conditional
writes (`If-Match` header). When two people run `terraform apply` simultaneously, the second
one fails immediately with a lock error rather than corrupting the state file.

DynamoDB-based locking is **deprecated** and will be removed in a future Terraform version.
Do not use it for new deployments.

Source: https://developer.hashicorp.com/terraform/language/backend/s3

### IAM permissions required for the Terraform execution role

The role that runs Terraform needs these permissions on the state bucket:

```json
{
  "Effect": "Allow",
  "Action": [
    "s3:GetObject",
    "s3:PutObject",
    "s3:DeleteObject",
    "s3:ListBucket"
  ],
  "Resource": [
    "arn:aws:s3:::your-state-bucket",
    "arn:aws:s3:::your-state-bucket/ebs-savings-dashboard/terraform.tfstate",
    "arn:aws:s3:::your-state-bucket/ebs-savings-dashboard/terraform.tfstate.tflock"
  ]
}
```

**Critical:** The `.tflock` file needs its own explicit permissions (`GetObject`, `PutObject`,
`DeleteObject`). If your state bucket policy is tightly scoped and only covers the `.tfstate`
file, locking will fail silently and state corruption can occur.

### If your org already has a Terraform state bucket

Edit `infra/backend.tf` and uncomment the backend block:

```hcl
terraform {
  backend "s3" {
    bucket       = "yourorg-terraform-state-123456789012"
    key          = "ebs-savings-dashboard/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true   # S3-native locking — no DynamoDB table needed
  }
}
```

Then initialise:
```bash
cd infra
terraform init
```

### If you need to create a state bucket (first time only)

`infra/backend.tf` includes bootstrap resources that create the state bucket itself.
Run once with the local backend, then migrate:

```bash
# Step 1: Apply with local state to create the bucket
cd infra
terraform init
terraform apply -var="org_name=yourorg" -var="bootstrap_state_bucket=true"

# Note the bucket name output, then uncomment the backend block in backend.tf

# Step 2: Migrate local state into the new S3 bucket
terraform init -migrate-state
```

After migration, the local `terraform.tfstate` file is no longer authoritative. All team
members run `terraform init` to pick up the remote backend.

---

## 4. Step 2 — KMS Encryption Keys

Located in: `infra/modules/kms/main.tf`

### Why four separate keys

| Key name | Encrypts | Why separate |
|---|---|---|
| `cur_key` | CUR S3 bucket (billing data) | Billing data is the most sensitive — separate key allows independent access revocation |
| `athena_key` | Athena results bucket | Query results contain per-account cost breakdowns |
| `lambda_key` | Lambda environment variables | Protects config values at rest |
| `frontend_logs_key` | CloudFront access logs | Logs contain user IPs and request patterns |

Using separate keys means you can rotate, disable, or audit access to each independently.
With a shared key, revoking access for one purpose revokes it for all.

### Key rotation

All four keys have automatic rotation enabled. As of 2024, AWS KMS supports **custom rotation
periods** between **90 and 2,560 days** (not just annual). The Terraform resource:

```hcl
resource "aws_kms_key" "cur" {
  description              = "EBS dashboard — CUR data encryption"
  enable_key_rotation      = true
  rotation_period_in_days  = 365   # default annual; change to 90 for stricter compliance
  deletion_window_in_days  = 90    # 90-day safety window before permanent deletion
}
```

**Important notes on KMS rotation:**
- Rotation only changes the key *material* (the cryptographic secret). The Key ID stays the same.
  Your applications do not need code changes when a key rotates.
- Old key material is retained forever — AWS uses it automatically to decrypt data encrypted
  with the old material. You never lose access to existing data.
- AWS does NOT rotate the data keys that KMS generated, and does NOT re-encrypt your data.
  Rotation only protects new data going forward.
- KMS keys cost ~$1/month each. After the 2nd rotation, extra key material versions do not
  add to the monthly cost.

Source: https://docs.aws.amazon.com/kms/latest/developerguide/rotate-keys.html

---

## 5. Step 3 — AWS Data Exports (CUR 2.0)

Located in: `infra/modules/cur/main.tf`

### What changed: CUR is now "AWS Data Exports"

The AWS console previously had a "Cost and Usage Reports" page. That has been renamed to
**Billing → Data Exports**. The underlying data (CUR 2.0) is the same, but the console
navigation and API have changed.

- **Old API:** `aws cur describe-report-definitions` (legacy CUR — still works but deprecated)
- **New API:** `aws bcm-data-exports list-exports` (CUR 2.0 via Data Exports)

CUR 2.0 improvements over legacy CUR:
- Fixed schema (columns never change month to month — essential for stable Athena queries)
- `bill_payer_account_name` and `line_item_usage_account_name` columns added (real account names,
  not just IDs — very useful for the By Account tab)
- Nested columns for `resource_tags`, `cost_category`, `product`, `discount`
- Parquet output (same as before)

### If CUR 2.0 already exists at your org

Do not run this Terraform module. Get the details from your FinOps team:

```bash
aws bcm-data-exports list-exports --region us-east-1 \
  --query 'Exports[*].{Name:Name,S3Bucket:DestinationConfigurations.S3Destination.S3Bucket,Prefix:DestinationConfigurations.S3Destination.S3Prefix}'
```

Replace the `module "cur"` block in `infra/main.tf` with locals pointing at the existing bucket:

```hcl
# infra/main.tf — use when CUR already exists
locals {
  cur_bucket_name = "your-existing-cur-bucket-name"
  cur_bucket_arn  = "arn:aws:s3:::your-existing-cur-bucket-name"
  cur_s3_prefix   = "your-export-prefix"
}
# Then update module "athena" to reference local.cur_bucket_name / local.cur_bucket_arn
```

### If CUR 2.0 does not exist yet

The `infra/modules/cur/main.tf` Terraform module creates:
1. S3 bucket with KMS encryption, versioning, and lifecycle tiering
   (90 days → Standard-IA, 365 days → Glacier IR, 90 days noncurrent expiry)
2. Bucket policy allowing `billingreports.amazonaws.com` to write files
3. SSL-only policy (denies all non-HTTPS access)
4. CUR 2.0 report definition

**The CUR API only works in us-east-1.** This is why the module uses a `provider = aws.us_east_1`
alias — it creates the report in us-east-1 even if all your other resources are in another region.

After enabling: AWS starts writing the next day. Request a 36-month backfill via support
(see Section 2c) immediately — do not wait.

### June 2026 update: you can now modify existing exports

Previously, changing a CUR 2.0 export configuration (e.g. adding a column) required deleting
and recreating it. As of June 2026, AWS supports updating an existing export's table
configuration via console and CLI without deletion. If you need to add columns later:

```bash
aws bcm-data-exports update-export \
  --export-arn <arn> \
  --export '{"TableConfigurations": {"CUR2_0": {"TIME_GRANULARITY": "HOURLY", "INCLUDE_RESOURCES": "TRUE"}}}'
```

Source: https://docs.aws.amazon.com/cur/latest/userguide/what-is-data-exports.html

---

## 6. Step 4 — Glue Crawler and Athena

Located in: `infra/modules/athena/main.tf`

### What Glue does and why it is needed

Parquet files in S3 have no schema metadata that Athena can read on its own. Glue reads
the files, detects column names and data types, and registers a table in the Glue Data Catalog.
Athena then queries that catalog to know what columns exist before running any SQL.

Without running the crawler at least once, Athena cannot query the data — it does not know
the table exists.

The crawler:
- Runs daily at 6am UTC (`cron(0 6 * * ? *)`)
- Updates the table schema if AWS adds new CUR 2.0 columns
- Creates table named after the S3 path prefix (e.g. `synthetic_report` or `cost_and_usage`)

**Run it manually once immediately after deployment** — do not wait for the first scheduled run:

```bash
CRAWLER=$(cd infra && terraform output -raw crawler_name)
aws glue start-crawler --name $CRAWLER

# Poll until READY (takes ~2 minutes)
watch -n 10 "aws glue get-crawler --name $CRAWLER --query 'Crawler.State' --output text"
# States: RUNNING → STOPPING → READY
```

**Check the table name the crawler created** — it will be used as the `CUR_TABLE` Lambda
environment variable:

```bash
aws glue get-tables --database-name cur_db --query 'TableList[*].Name'
```

### What Athena does

Athena is serverless SQL. You are charged $5 per TB of data scanned. Parquet with Snappy
compression is 10-20x smaller than CSV, so costs are very low.

The workgroup enforces:
- **Engine v3** — Athena's current engine (based on Trino). Supports modern SQL functions.
- **10 GB scan cap** — any query scanning more than 10 GB is killed immediately. Protects
  against a bad query that accidentally scans years of data. For a 400-account org with
  12 months of Parquet, expect 2-5 GB per full scan. 10 GB is safe headroom.
- **Results bucket** — Athena writes output files here. Lambda reads them back. Auto-deleted
  after 3 days by a lifecycle rule.

---

## 7. Step 5 — Lambda Function

Located in: `infra/modules/lambda/main.tf` and `infra/modules/lambda/src/handler.py`

### What the function does — step by step

1. Receives HTTP GET from API Gateway. Query params: `months` (default 18), `region` (default all)
2. Formats the SQL — inserts database name, table name, months, and region filter
3. Calls `athena:StartQueryExecution` — submits the SQL, receives a query execution ID
4. Polls `athena:GetQueryExecution` every 2 seconds until state is SUCCEEDED or FAILED
5. Reads the CSV result file from the results S3 bucket
6. Builds 5 aggregations from the rows: monthly trend, KPIs, accounts, regions, volume types
7. Calls `ec2:DescribeVolumes` in the management account for the Volume Inventory tab
8. For each member account: calls `sts:AssumeRole` to get temporary credentials, then
   calls `ec2:DescribeVolumes` in that account, enriches volume data with instance names
9. Returns a single JSON payload to API Gateway

### Configuration

| Setting | Value | Reason |
|---|---|---|
| Runtime | Python 3.12 | Latest stable Lambda Python runtime |
| Timeout | 60 seconds | Athena queries can take 10-30s; EC2 calls across 400 accounts add more |
| Memory | 512 MB | Comfortable headroom for JSON processing |
| X-Ray tracing | Active | Shows how long each step takes — useful for diagnosing slow queries |
| DLQ | SQS queue | Captures failed async invocations for debugging |
| VPC | Optional | Enable if your org policy requires Lambda inside a VPC. Add NAT Gateway — Lambda in a VPC cannot reach AWS service APIs without it. |

### Environment variables

| Variable | Example | What it does |
|---|---|---|
| `ATHENA_DATABASE` | `cur_db` | Glue database name |
| `ATHENA_WORKGROUP` | `yourorg-prod-workgroup` | Athena workgroup to run queries in |
| `RESULTS_BUCKET` | `yourorg-athena-results-123456789012` | Where Athena writes results |
| `CUR_TABLE` | `cost_and_usage` | Glue table name — check with `aws glue get-tables` |
| `MEMBER_ROLE_NAME` | `EBSDashboardReadRole` | Role Lambda assumes in each member account |
| `ORG_ID` | `o-ab1cd2ef34` | AWS Org ID — scopes cross-account trust |

### IAM permissions — exact and least-privilege

```
ATHENA
  athena:StartQueryExecution  → scoped to workgroup ARN only
  athena:GetQueryExecution    → scoped to workgroup ARN only
  athena:GetQueryResults      → scoped to workgroup ARN only
  athena:StopQueryExecution   → scoped to workgroup ARN only

GLUE (Athena needs catalog access at query time — cannot be scoped further)
  glue:GetTable               → *
  glue:GetDatabase            → *
  glue:GetPartitions          → *

S3 — CUR bucket (read only)
  s3:GetObject                → arn:aws:s3:::cur-bucket-name/*
  s3:ListBucket               → arn:aws:s3:::cur-bucket-name
  s3:GetBucketLocation        → arn:aws:s3:::cur-bucket-name

S3 — Results bucket (read + write + delete)
  s3:PutObject                → arn:aws:s3:::results-bucket-name/*
  s3:GetObject                → arn:aws:s3:::results-bucket-name/*
  s3:DeleteObject             → arn:aws:s3:::results-bucket-name/*
  s3:ListBucket               → arn:aws:s3:::results-bucket-name
  s3:GetBucketLocation        → arn:aws:s3:::results-bucket-name
  s3:AbortMultipartUpload     → arn:aws:s3:::results-bucket-name/*
  s3:ListMultipartUploadParts → arn:aws:s3:::results-bucket-name/*

KMS (if using CMK encryption)
  kms:GenerateDataKey         → CUR key ARN and Athena key ARN
  kms:Decrypt                 → CUR key ARN and Athena key ARN

EC2 (cannot be resource-scoped — AWS restriction on Describe actions)
  ec2:DescribeVolumes         → *
  ec2:DescribeInstances       → *
  ec2:DescribeSnapshots       → *

STS (to assume role in member accounts)
  sts:AssumeRole              → arn:aws:iam::*:role/EBSDashboardReadRole
```

---

## 8. Step 6 — API Gateway

Located in: `infra/modules/api_gateway/main.tf`

### HTTP API v2 — why not REST API

HTTP API (v2) is the current AWS recommendation for new Lambda-backed APIs:
- 70% cheaper than REST API ($1.00/million vs $3.50/million requests)
- Lower latency (no response mapping layer)
- Supports JWT authorizers natively (no custom Lambda authorizer needed)
- Supports Lambda payload format 2.0 (simpler request/response structure)

### The single route

```
GET /ebs-savings
  ?months=18        how far back to query (default: 18)
  ?region=all       filter to a region, or "all" (default: all)
```

### Throttling

```hcl
throttling_burst_limit = 50   # max concurrent requests at any instant
throttling_rate_limit  = 10   # sustained requests per second
```

Adjust these based on your expected user count. For a 400-person FinOps team where 20 users
might be active simultaneously: `burst=100, rate=20` is reasonable.

### CORS

Lock CORS to your specific CloudFront domain in production:

```hcl
cors_configuration {
  allow_origins = ["https://ebs-savings.internal.yourcompany.com"]
  allow_methods = ["GET", "OPTIONS"]
  allow_headers = ["Content-Type", "Authorization"]
}
```

Using `*` for allowed origins means any website could call your API. In production
always specify the exact domain.

### JWT Authorizer

When Cognito is configured, every request must include:
```
Authorization: Bearer <cognito-access-token>
```

API Gateway validates the token against Cognito's JWKS endpoint automatically —
no custom code needed. Invalid or expired tokens get a 401 before Lambda is even invoked.

---

## 9. Step 7 — Cognito Authentication

Located in: `infra/modules/api_gateway/main.tf` (JWT authorizer section)

### Why authentication is required

Without auth, anyone who finds the API URL can query your entire organisation's billing data.
This includes monthly spend per account, volume details, and cost trends — sensitive
financial information.

### If your org already has a Cognito User Pool

```bash
# Find existing user pools
aws cognito-idp list-user-pools --max-results 20

# Find app clients for a given pool
aws cognito-idp list-user-pool-clients --user-pool-id us-east-1_XXXXXXXXX
```

Pass the IDs as Terraform variables:
```hcl
cognito_user_pool_id  = "us-east-1_AbCdEfGhI"
cognito_app_client_id = "1234567890abcdefghijklmnop"
```

### If you need to create a new User Pool

```bash
# Create user pool with secure password policy
aws cognito-idp create-user-pool \
  --pool-name ebs-dashboard-users \
  --auto-verified-attributes email \
  --username-attributes email \
  --mfa-configuration OPTIONAL \
  --sms-mfa-configuration '{"SmsAuthenticationMessage":"Your code is {####}"}' \
  --policies '{
    "PasswordPolicy": {
      "MinimumLength": 12,
      "RequireUppercase": true,
      "RequireLowercase": true,
      "RequireNumbers": true,
      "RequireSymbols": true,
      "TemporaryPasswordValidityDays": 7
    }
  }' \
  --region us-east-1

# Create app client — no client secret (SPA apps use PKCE, not client secrets)
aws cognito-idp create-user-pool-client \
  --user-pool-id <pool-id> \
  --client-name ebs-dashboard-spa \
  --no-generate-secret \
  --allowed-o-auth-flows code \
  --allowed-o-auth-scopes openid email profile \
  --callback-urls '["https://ebs-savings.internal.yourcompany.com/callback"]' \
  --logout-urls '["https://ebs-savings.internal.yourcompany.com"]' \
  --supported-identity-providers COGNITO \
  --allowed-o-auth-flows-user-pool-client \
  --explicit-auth-flows ALLOW_REFRESH_TOKEN_AUTH \
  --region us-east-1
```

### Adding users

```bash
aws cognito-idp admin-create-user \
  --user-pool-id <pool-id> \
  --username engineer@yourcompany.com \
  --user-attributes Name=email,Value=engineer@yourcompany.com Name=email_verified,Value=true \
  --temporary-password TempPass123! \
  --message-action SUPPRESS \
  --region us-east-1
```

The user is prompted to set a permanent password on first login.

### How the token flow works

1. User opens the dashboard → React redirects to Cognito hosted UI
2. User logs in → Cognito issues an access token (valid 1 hour by default)
3. React stores the token in memory (not localStorage — avoids XSS token theft)
4. Every API call includes `Authorization: Bearer <token>`
5. API Gateway validates the token against Cognito's public JWKS keys
6. If expired → 401 → React redirects to login
7. Refresh tokens (valid 30 days by default) allow silent re-authentication

---

## 10. Step 8 — CloudFront, WAF, and S3 Frontend

Located in: `infra/modules/frontend/main.tf`

### S3 bucket (frontend assets)

Stores the compiled React app output from `npm run build`.
- Completely private — no public S3 access whatsoever
- Versioning enabled — allows rollback to a previous deploy
- CloudFront reads it via OAC using SigV4 request signing
- `Object Ownership = Bucket owner enforced` (the default for new buckets) — required for OAC

### Why OAC and not the older OAI

OAC (Origin Access Control) is the current AWS recommendation (OAI is being phased out).
OAC is better because:
- Supports SSE-KMS encrypted S3 buckets (OAI does not)
- Uses SigV4 signing (stronger security than unsigned OAI requests)
- Supports all S3 regions and all S3 features

Source: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html

### CloudFront distribution

| Setting | Value | Reason |
|---|---|---|
| Price class | `PriceClass_100` | US + EU edge locations. Change to `PriceClass_All` for APAC users. |
| Default root | `index.html` | Serves the React app entry point |
| HTTPS | Redirect HTTP → HTTPS | No plaintext traffic |
| SPA routing | 403/404 → 200 index.html | React Router handles routes client-side |
| Static assets cache | 1 year (max-age=31536000) | Vite puts content hash in filenames — safe to cache forever |
| /api/* cache | 0 (no cache) | API data must always be fresh |

### WAF — deploy in Count mode first, then Block

**Do not deploy WAF rules straight to Block mode in production.**
AWS explicitly recommends testing in Count mode first to identify false positives.

**Phase 1 — Count mode (first 1-2 weeks after launch):**

```hcl
rule {
  name     = "AWSManagedRulesCommonRuleSet"
  priority = 1
  override_action { count {} }   # log only, do not block
  ...
}
```

Monitor in CloudWatch:
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/WAFV2 \
  --metric-name CountedRequests \
  --dimensions Name=WebACL,Value=yourorg-prod-frontend-waf Name=Region,Value=CloudFront \
  --start-time 2026-07-01T00:00:00Z \
  --end-time 2026-07-07T00:00:00Z \
  --period 86400 --statistics Sum
```

**Phase 2 — Switch to Block mode (after confirming no false positives):**

```hcl
rule {
  name     = "AWSManagedRulesCommonRuleSet"
  priority = 1
  override_action { none {} }   # honour the rule's own block action
  ...
}
```

### WAF rules in this stack

| Rule | Priority | Blocks | Monthly cost |
|---|---|---|---|
| `AWSManagedRulesCommonRuleSet` | 1 | SQL injection, XSS, path traversal, bad user agents | Included in WAF base ($5/mo) |
| `AWSManagedRulesKnownBadInputsRuleSet` | 2 | Log4j exploits, Spring4Shell, known CVEs | Included in WAF base |
| `RateLimitPerIP` | 3 | IPs making >2000 requests per 5 minutes | Included in WAF base |

WAF base cost: ~$5/month + $1/million requests evaluated.

Source: https://docs.aws.amazon.com/waf/latest/developerguide/waf-managed-protections-best-practices.html

---

## 11. Step 9 — Cross-Account IAM Role (400+ Accounts)

Located in: `infra/modules/cross_account_role/main.tf`
Deployment script: `infra/cross_account_roles/generate_providers.py`

### Why this role is needed

Lambda runs in the Management Account. EBS volumes live in 400+ member accounts.
Lambda cannot describe volumes in another account without permission from that account.

The solution: create `EBSDashboardReadRole` in every member account. Lambda assumes
that role temporarily via STS, gets short-lived credentials (1 hour max), calls EC2,
then the credentials expire automatically. No permanent access is granted.

### The role (identical in every member account)

```hcl
# Trust policy — who can assume this role
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [var.lambda_role_arn]   # only the Lambda role in mgmt account
    }
    # Defence in depth: even if someone has the Lambda role ARN, they cannot
    # assume this role from outside your org
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.org_id]
    }
  }
}

# Permissions — read-only EC2 describe actions only
resource "aws_iam_role_policy" "ebs_read" {
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:DescribeVolumes",
        "ec2:DescribeInstances",
        "ec2:DescribeSnapshots",
        "ec2:DescribeAvailabilityZones",
        "ec2:DescribeRegions",
      ]
      Resource = ["*"]   # EC2 Describe actions cannot be scoped to specific resources
    }]
  })
}
```

### Deploying to 400 accounts with HCP Terraform

**Option A — Terraform Stacks (HCP Terraform Plus tier — recommended)**

Stacks is the purpose-built HCP Terraform feature for deploying the same infrastructure
across many accounts without generating boilerplate files.

```hcl
# infra/cross_account_roles/stack.tf
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 5.40"
  }
}

# OIDC dynamic credentials — no static AWS keys stored anywhere
identity_tokens {
  aws = {
    audience = ["aws.workload.identity"]
  }
}

# for_each over all member account IDs — native to Stacks, no boilerplate needed
deployment "member_accounts" {
  for_each = var.member_account_ids

  inputs = {
    role_arn        = "arn:aws:iam::${each.value}:role/TerraformExecutionRole"
    lambda_role_arn = var.lambda_role_arn
    org_id          = var.org_id
  }
}
```

HCP Terraform workspace variables to set:
```
TFC_AWS_PROVIDER_AUTH    = true
TFC_AWS_RUN_ROLE_ARN     = arn:aws:iam::MGMT_ACCOUNT:role/TerraformExecutionRole
```

Terraform tracks a separate state per deployment (per account) automatically.
When a new account is added to `member_account_ids`, the next `terraform apply` creates
the role in that account. When an account is removed, `terraform apply` deletes the role.

**Option B — generate_providers.py (HCP Terraform Free/Standard — fallback)**

If your org is not on Plus tier, use the script that generates static provider aliases:

```bash
# Get all active account IDs from AWS Organizations
aws organizations list-accounts \
  --query 'Accounts[?Status==`ACTIVE`].Id' \
  --output text | tr '\t' '\n' > accounts.txt

# Generate providers.tf and main.tf for all 400 accounts
cd infra/cross_account_roles
python generate_providers.py \
  --accounts accounts.txt \
  --lambda-role arn:aws:iam::MGMT_ACCOUNT_ID:role/yourorg-prod-lambda \
  --org-id o-ab1cd2ef34 \
  --exec-role TerraformExecutionRole   # ask your platform team for the correct name

# Commit the generated files
git add providers.tf main.tf
git commit -m "Generate cross-account role providers for $(wc -l < accounts.txt) accounts"
git push
```

HCP Terraform picks up the commit, plans the changes, and deploys `EBSDashboardReadRole`
into all accounts on `terraform apply`.

Re-run `generate_providers.py` whenever accounts are added or removed and commit again.

### Pre-requisite: Terraform execution role in each member account

Both options require a role that Terraform can assume in each member account. Your org
almost certainly already has one. Common names:

| Name | Created by |
|---|---|
| `TerraformExecutionRole` | Most platform teams |
| `OrganizationAccountAccessRole` | AWS Organizations (automatic) |
| `AWSControlTowerExecution` | AWS Control Tower |

Ask your platform team: "What IAM role name do we use for Terraform to deploy into member accounts?"

---

## 12. Step 10 — HCP Terraform OIDC Dynamic Credentials

**This replaces storing static AWS access keys in HCP Terraform workspace variables.**
Static keys are a security risk — they do not expire, and if leaked, grant permanent access.
OIDC credentials are short-lived (expire when the Terraform run ends) and cannot be reused.

Source: https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/aws-configuration

### Step 1 — Create the OIDC provider in AWS (once per AWS account)

```bash
aws iam create-open-id-connect-provider \
  --url https://app.terraform.io \
  --client-id-list aws.workload.identity \
  --thumbprint-list 9e99a48a9960b14926bb7f3b02e22da2b0ab7280 \
  --region us-east-1
```

### Step 2 — Create the IAM role HCP Terraform assumes

```hcl
data "aws_iam_policy_document" "hcp_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.hcp.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "app.terraform.io:aud"
      values   = ["aws.workload.identity"]
    }
    condition {
      test     = "StringLike"
      variable = "app.terraform.io:sub"
      # Scope to your specific HCP org and project — do not use * in production
      values   = ["organization:YOUR_HCP_ORG:project:YOUR_PROJECT:workspace:ebs-savings-dashboard:run_phase:*"]
    }
  }
}

resource "aws_iam_role" "hcp_terraform" {
  name               = "HCPTerraformRole-EBSDashboard"
  assume_role_policy = data.aws_iam_policy_document.hcp_trust.json
}

# Attach AdministratorAccess or a scoped policy for what this deployment needs
resource "aws_iam_role_policy_attachment" "hcp_admin" {
  role       = aws_iam_role.hcp_terraform.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
```

### Step 3 — Set HCP Terraform workspace environment variables

In HCP Terraform → Workspace → Variables → Environment variables:

| Variable | Value | Sensitive? |
|---|---|---|
| `TFC_AWS_PROVIDER_AUTH` | `true` | No |
| `TFC_AWS_RUN_ROLE_ARN` | `arn:aws:iam::ACCOUNT_ID:role/HCPTerraformRole-EBSDashboard` | No |

That is all. Remove any existing `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` variables.
HCP Terraform will now use OIDC to generate short-lived credentials for each run.

### Step 4 — Verify the AWS provider has no hardcoded credentials

```hcl
# infra/versions.tf — correct: no credentials block
provider "aws" {
  region = var.aws_region
  # HCP Terraform injects credentials via OIDC automatically
  # Do NOT add access_key or secret_key here
}
```

---

## 13. Step 11 — Build and Deploy the React App

### Set production environment variables

Create `ebs-savings-dashboard/.env.production`:

```bash
VITE_API_URL=https://ebs-savings.internal.yourcompany.com/api
VITE_USE_MOCK=false
```

If not using a custom domain, use the API Gateway URL from Terraform output:
```bash
cd infra && terraform output api_invoke_url
# Paste that URL as VITE_API_URL
```

### Build

```bash
cd ebs-savings-dashboard
npm install
npm run build
# Output: ebs-savings-dashboard/dist/
# Vite puts content hashes in filenames: app.a1b2c3d4.js
# This means JS/CSS can be cached forever without stale content issues
```

### Upload to S3

```bash
FRONTEND_BUCKET=$(cd ../infra && terraform output -raw frontend_bucket_name)

# Upload everything
aws s3 sync dist/ s3://$FRONTEND_BUCKET/ --delete

# Override cache for index.html — must never be cached (it references the hashed assets)
aws s3 cp dist/index.html s3://$FRONTEND_BUCKET/index.html \
  --cache-control "no-cache, no-store, must-revalidate" \
  --content-type "text/html"

# JS, CSS, and other hashed assets can be cached for 1 year
aws s3 cp dist/assets/ s3://$FRONTEND_BUCKET/assets/ \
  --recursive \
  --cache-control "public, max-age=31536000, immutable"
```

### Invalidate CloudFront cache after every deploy

CloudFront caches the old files at edge locations. Force an update:

```bash
DIST_ID=$(cd ../infra && terraform output -raw cloudfront_distribution_id)

aws cloudfront create-invalidation \
  --distribution-id $DIST_ID \
  --paths "/*"

# Check status (takes ~30 seconds to propagate globally)
aws cloudfront list-invalidations --distribution-id $DIST_ID \
  --query 'InvalidationList.Items[0].Status'
```

---

## 14. Step 12 — DNS and Custom Domain

### Why a custom domain

Without it your dashboard URL is `https://d3xxxxxxxxxxxxxxxxx.cloudfront.net` — hard to
share and not trustworthy-looking to stakeholders.

### Step 1 — Request ACM certificate (must be in us-east-1)

CloudFront requires ACM certificates in us-east-1 regardless of where your app is deployed.

```bash
aws acm request-certificate \
  --domain-name ebs-savings.internal.yourcompany.com \
  --validation-method DNS \
  --region us-east-1
```

### Step 2 — Add the DNS validation CNAME

ACM gives you a CNAME record to prove domain ownership. Add it in Route 53:

```bash
# Get the validation record
aws acm describe-certificate \
  --certificate-arn <arn> \
  --region us-east-1 \
  --query 'Certificate.DomainValidationOptions[0].ResourceRecord'
```

Add the `Name` → `Value` CNAME to your DNS. Validation takes 5-10 minutes.

### Step 3 — Get the certificate ARN

```bash
aws acm list-certificates \
  --region us-east-1 \
  --query 'CertificateSummaryList[?DomainName==`ebs-savings.internal.yourcompany.com`].CertificateArn'
```

### Step 4 — Add to Terraform variables

```hcl
domain_name         = "ebs-savings.internal.yourcompany.com"
acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123-def"
```

Run `terraform apply`. CloudFront will now serve the dashboard at your domain.

### Step 5 — Add the DNS CNAME to point at CloudFront

```bash
# Get the CloudFront domain name
cd infra && terraform output cloudfront_domain_name
# Outputs something like: d3xxxxxxxxxxxxxxxxx.cloudfront.net
```

In Route 53 (or your DNS provider), add:
```
ebs-savings.internal.yourcompany.com  CNAME  d3xxxxxxxxxxxxxxxxx.cloudfront.net
```

---

## 15. Terraform Variables Reference

Create `infra/terraform.tfvars` (do not commit to git — add to `.gitignore`):

```hcl
# ── Required ──────────────────────────────────────────────────────────────────
org_name = "yourorg"           # short slug — used in all resource names

# ── Region ────────────────────────────────────────────────────────────────────
aws_region  = "us-east-1"
environment = "prod"           # dev | staging | prod

# ── Networking (optional — leave empty to deploy Lambda outside VPC) ──────────
vpc_id             = "vpc-xxxxxxxxxxxxxxxx"
private_subnet_ids = ["subnet-aaaaaaaaaaaaaaaa", "subnet-bbbbbbbbbbbbbbbb"]

# ── Authentication ────────────────────────────────────────────────────────────
cognito_user_pool_id  = "us-east-1_AbCdEfGhI"
cognito_app_client_id = "1234567890abcdefghijklmnopqrstuvwxyz"

# ── Custom domain (optional) ──────────────────────────────────────────────────
domain_name         = "ebs-savings.internal.yourcompany.com"
acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/abc-123"

# ── Cross-account ──────────────────────────────────────────────────────────────
org_id = "o-ab1cd2ef34"        # from: aws organizations describe-organization

# ── Athena safety (10 GB default — increase for very large orgs) ──────────────
athena_scan_limit_bytes = 10737418240   # 10 GB
```

---

## 16. Cost Estimate

Estimated monthly costs for a 400-account org with 18 months of CUR data:

| Service | Estimate | Basis |
|---|---|---|
| S3 — CUR data | $5–20/mo | 400 accounts × 18 months ≈ 3-8 GB compressed Parquet. S3 Standard: $0.023/GB |
| S3 — Athena results | < $1/mo | 3-day lifecycle deletes files. Few GB total at any time. |
| S3 — Frontend | < $1/mo | ~5 MB of static assets |
| Glue crawler | < $1/mo | 1 DPU × ~2 min/day × 30 days = 1 DPU-hour/month @ $0.44/DPU-hour |
| Athena | < $2/mo | $5/TB scanned. 100 queries × avg 50 MB per query = 5 GB = $0.025 |
| Lambda | < $1/mo | Well within 1M free tier requests. 512 MB × 30s avg = low cost. |
| API Gateway | < $1/mo | $1/million requests. Internal dashboard = low traffic. |
| CloudFront | $1–5/mo | Depends on user count and geography |
| WAF | ~$6/mo | $5 base + $1/million requests evaluated |
| KMS | ~$4/mo | $1/key/month × 4 keys. Key material versions after 2nd rotation are free. |
| CloudWatch Logs | $1–3/mo | Lambda + API GW + WAF logs @ $0.50/GB ingested |
| **Total** | **~$20–45/mo** | Scales with org size and active user count |

CUR data storage is the largest variable cost. A very large org (1000+ accounts, 36 months)
could push S3 costs to $50-100/month. Run `aws s3 ls s3://your-cur-bucket --recursive --summarize`
to check your actual data size before estimating.

---

## 17. Personal Test vs Production — Side by Side

| | Personal Test (`infra/test/`) | Production (`infra/`) |
|---|---|---|
| CUR data | Fake Parquet from `generate_mock_cur.py` | Real billing data written daily by AWS |
| Console location | N/A — manually uploaded | Billing → Data Exports |
| Authentication | None (open API) | Cognito JWT — must log in |
| HCP Terraform auth | N/A (local apply) | OIDC dynamic credentials — no static keys |
| Frontend hosting | `npm run dev` on laptop | CloudFront → S3 — permanent URL |
| WAF | None | 3 managed rule groups (start in Count, then Block) |
| KMS | AWS-managed keys (SSE-S3) | Customer-managed KMS keys (4 CMKs) |
| State backend | Local `terraform.tfstate` | S3 with `use_lockfile = true` — no DynamoDB |
| Cross-account | Not deployed | HCP Terraform Stacks or generate_providers.py |
| Volume inventory | Empty (no real volumes) | Real volumes from 400+ accounts |
| Athena scan cap | 1 GB | 10 GB |
| Glue schedule | Manual trigger | Daily at 6am UTC |
| Cost | ~$0.05 total | ~$20–45/month |

---

## 18. Troubleshooting

### "Unable to verify/create output bucket"
**Cause:** Lambda IAM role is missing `s3:GetBucketLocation` on the Athena results bucket.
**Fix:**
```bash
aws iam put-role-policy --role-name <lambda-role-name> --policy-name ... \
  # Add s3:GetBucketLocation to the S3Results statement
```

### "Table does not exist" (Athena error)
**Cause:** Glue crawler has not run yet, or ran before data was uploaded to S3.
**Fix:**
```bash
aws glue start-crawler --name <crawler-name>
# Wait ~2 minutes, check state is READY, then retry the API
```

### "TYPE_MISMATCH: Cannot check if varchar is BETWEEN date and date"
**Cause:** The CUR table stores `line_item_usage_start_date` as a string (ISO 8601 with timezone).
**Fix:** The SQL must cast it: `date(substr(line_item_usage_start_date, 1, 10))`.
Check that the latest `handler.py` is deployed — redeploy Lambda if the old version is running.

### "Athena query FAILED: SCHEMA_NOT_SUPPORTED"
**Cause:** CUR was created with `Format = CSV` not `Format = Parquet`.
**Fix:** Create a new Data Export with Parquet format. CSV is not efficient for Athena.

### Dashboard loads but all values are zero
**Steps to diagnose:**
1. Open browser DevTools → Network tab → find the `/ebs-savings` request → check response body
2. If `{"kpi": {}, "monthly_trend": [], ...}` — Athena query returned 0 rows
   - Check `months` parameter — increase to 18 or 24 to widen the date window
   - Check the date format in your Parquet — must be `YYYY-MM-DD` prefix
3. If `{"message": "Internal Server Error"}` — check Lambda CloudWatch logs:
   ```bash
   aws logs tail /aws/lambda/<function-name> --since 10m --format short
   ```

### CORS error in browser console
**Symptom:** `Access-Control-Allow-Origin` header missing or wrong value.
**Fix:** Ensure `allowed_origins` in API Gateway matches the exact URL your frontend is served from.
If using CloudFront with a custom domain, the origin must be `https://yourdomain.com` (no trailing slash).

### WAF blocking legitimate users
**Symptom:** Users get blocked, 403 responses logged in WAF.
**Fix:** Switch the blocking rule to `override_action { count {} }` temporarily.
Check CloudWatch WAF metrics to see which rule is triggering:
```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/WAFV2 \
  --metric-name BlockedRequests \
  --dimensions Name=Rule,Value=AWSManagedRulesCommonRuleSet ...
```
Add a rule exception if the block is a false positive.

### HCP Terraform OIDC auth fails ("no valid credential sources")
**Cause:** `TFC_AWS_PROVIDER_AUTH` and `TFC_AWS_RUN_ROLE_ARN` not set in workspace variables,
or the IAM trust policy subject condition does not match your HCP org/project/workspace names.
**Fix:** Verify the subject condition in the IAM trust policy exactly matches:
`organization:YOUR_HCP_ORG:project:YOUR_PROJECT:workspace:YOUR_WORKSPACE:run_phase:*`
Names are case-sensitive.

### ".tflock" permission denied during terraform apply
**Cause:** The Terraform execution role has `s3:PutObject` on the state file but not on
the `.tflock` file path (they are separate objects in S3).
**Fix:** Add `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` explicitly for:
`arn:aws:s3:::your-state-bucket/path/to/terraform.tfstate.tflock`

### CloudFront serves old version after redeployment
**Fix:**
```bash
aws cloudfront create-invalidation --distribution-id <id> --paths "/*"
# Wait ~30 seconds for global propagation
```

### Cross-account role assumption fails
```bash
# Verify role exists in member account
aws iam get-role --role-name EBSDashboardReadRole \
  --profile <member-account-profile>

# Verify trust policy includes Lambda role ARN and correct org ID
aws iam get-role --role-name EBSDashboardReadRole \
  --profile <member-account-profile> \
  --query 'Role.AssumeRolePolicyDocument'
```

---

## Sources — All Verified June 30, 2026

- [AWS Data Exports — What is AWS Data Exports](https://docs.aws.amazon.com/cur/latest/userguide/what-is-data-exports.html)
- [Migrating from CUR to CUR 2.0](https://docs.aws.amazon.com/cur/latest/userguide/dataexports-migrate.html)
- [CUR 2.0 table configuration update — June 2026](https://aws.amazon.com/about-aws/whats-new/2026/06/aws-cost-usage-report/)
- [Terraform S3 Backend — use_lockfile, DynamoDB deprecation](https://developer.hashicorp.com/terraform/language/backend/s3)
- [Rotate AWS KMS keys — custom rotation periods](https://docs.aws.amazon.com/kms/latest/developerguide/rotate-keys.html)
- [AWS KMS best practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/aws-kms-best-practices/data-protection-key-rotation.html)
- [CloudFront OAC — restrict access to S3 origin](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/private-content-restricting-access-to-s3.html)
- [AWS WAF managed rules best practices](https://docs.aws.amazon.com/waf/latest/developerguide/waf-managed-protections-best-practices.html)
- [HCP Terraform dynamic credentials with AWS (OIDC)](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/aws-configuration)
- [HCP Terraform Stacks — use cases](https://developer.hashicorp.com/terraform/language/stacks/use-cases)
- [Provision AWS resources across accounts using AssumeRole](https://developer.hashicorp.com/terraform/tutorials/aws/aws-assumerole)
