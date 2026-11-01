# EBS Savings Dashboard — Test Stack Architecture

## Data Flow

```
Your laptop
    │ generate_mock_cur.py uploads Parquet files
    ▼
┌─────────────────────────────────┐
│  S3 Bucket (CUR data)           │  ← stores the billing data
│  ebstest-cur-<account-id>       │
└─────────────────────────────────┘
    │ Glue crawler reads it
    ▼
┌─────────────────────────────────┐
│  Glue Database (cur_db)         │  ← creates a queryable schema
│  Glue Crawler                   │     "here are the columns"
└─────────────────────────────────┘
    │ Athena queries it
    ▼
┌─────────────────────────────────┐
│  Athena Workgroup               │  ← runs the SQL
│  S3 Bucket (results)            │  ← Athena writes results here
└─────────────────────────────────┘
    │ Lambda calls Athena
    ▼
┌─────────────────────────────────┐
│  Lambda Function                │  ← runs the Python handler
│  IAM Role + Policies            │     queries Athena, returns JSON
│  CloudWatch Log Group           │
└─────────────────────────────────┘
    │ API Gateway exposes it
    ▼
┌─────────────────────────────────┐
│  API Gateway (HTTP API)         │  ← public HTTPS endpoint
│  Route: GET /ebs-savings        │     your dashboard calls this
│  Stage: $default                │
└─────────────────────────────────┘
    │ dashboard fetches data
    ▼
React App (running on your laptop)
```

---

## Personal Account Test vs Real Environment

| | Personal Account Test | Real Environment (your org) |
|---|---|---|
| CUR data | `generate_mock_cur.py` writes fake Parquet files to S3 | AWS Billing writes real Parquet files to S3 automatically every day |
| Accounts | 5 fake accounts in mock data | 400+ real accounts via consolidated billing |
| Auth | None (open API for testing) | Cognito JWT |
| CloudFront + WAF | Not deployed (test only) | Deployed |
| KMS encryption | Not deployed (test only) | Deployed |

---

## All 21 Resources — What They Are and Why

### S3 — 5 resources

| Resource | Name | Why it exists |
|---|---|---|
| `aws_s3_bucket.cur` | `ebstest-cur-<account-id>` | Holds the CUR Parquet files (billing data). In production this is your existing billing bucket that AWS writes to daily. |
| `aws_s3_bucket_public_access_block.cur` | — | Blocks all public access to the CUR bucket. Billing data must never be public. |
| `aws_s3_bucket.results` | `ebstest-athena-results-<account-id>` | Athena cannot return query results directly — it writes them to S3 first. This bucket holds those output files. |
| `aws_s3_bucket_public_access_block.results` | — | Keeps query results private. |
| `aws_s3_bucket_lifecycle_configuration.results` | — | Auto-deletes Athena result files after 3 days. Without this, results accumulate forever and cost money. |

---

### Glue — 5 resources

| Resource | Name | Why it exists |
|---|---|---|
| `aws_glue_catalog_database.cur` | `cur_db` | A logical container. Athena uses Glue as its metadata store — without a database, Athena has nowhere to register the table. |
| `aws_iam_role.glue` | `ebstest-glue-role` | Glue needs permission to read your S3 bucket. AWS services cannot use your personal credentials — they need their own IAM role. |
| `aws_iam_role_policy_attachment.glue_service` | — | Attaches the AWS-managed `AWSGlueServiceRole` policy — gives Glue basic access to CloudWatch logs and Glue APIs. |
| `aws_iam_role_policy.glue_s3` | — | Explicitly allows Glue to `GetObject` and `ListBucket` on your CUR bucket. The managed policy above does not cover specific S3 buckets — you must add this separately. |
| `aws_glue_crawler.cur` | `ebstest-crawler` | Scans the Parquet files in S3, detects column names and data types, and registers a table called `cost_and_usage` in `cur_db`. Without this Athena does not know what columns exist and cannot run queries. |

---

### Athena — 1 resource

| Resource | Name | Why it exists |
|---|---|---|
| `aws_athena_workgroup.test` | `ebstest-workgroup` | A named context for running queries. Enforces where results are written (your results bucket), which SQL engine to use (v3), and a 1 GB scan cap so a bad query cannot scan gigabytes and run up a bill. |

---

### Lambda — 5 resources

| Resource | Name | Why it exists |
|---|---|---|
| `aws_iam_role.lambda` | `ebstest-lambda-role` | Lambda needs an identity to call Athena, read S3, and write logs. AWS services cannot use your personal credentials. |
| `aws_iam_role_policy_attachment.lambda_basic` | — | Allows Lambda to write logs to CloudWatch. Without this, if the function crashes you see nothing. |
| `aws_iam_role_policy.lambda` | — | Grants specific permissions: run Athena queries, read CUR bucket, write to results bucket, call EC2 DescribeVolumes for the inventory tab. Each permission is scoped as tightly as possible. |
| `aws_cloudwatch_log_group.lambda` | `/aws/lambda/ebstest-ebs-savings` | Pre-creates the log group with 7-day retention. If you skip this, Lambda auto-creates it with infinite retention and logs accumulate forever. |
| `aws_lambda_function.ebs_savings` | `ebstest-ebs-savings` | The Python function (`handler.py`) that runs the Athena SQL, waits for results, calls EC2 DescribeVolumes, and returns the JSON the dashboard expects. |

---

### API Gateway — 5 resources

| Resource | Name | Why it exists |
|---|---|---|
| `aws_apigatewayv2_api.test` | `ebstest-api` | Creates the HTTP API — the public HTTPS endpoint the React dashboard calls. Also configures CORS so the browser does not block cross-origin requests. |
| `aws_apigatewayv2_integration.lambda` | — | Wires the API to Lambda. API Gateway needs to know "when a request comes in, invoke this function". |
| `aws_apigatewayv2_route.ebs_savings` | `GET /ebs-savings` | Defines the specific path that triggers Lambda. All other paths return 404. |
| `aws_apigatewayv2_stage.test` | `$default` | A stage is a named deployment of the API. `$default` means requests hit the root URL directly with no `/prod` or `/v1` prefix. |
| `aws_lambda_permission.api_gw` | — | Even with the integration in place, Lambda requires an explicit resource-based policy allowing API Gateway to invoke it. Without this, every request gets a 403. |

---

## IAM Permissions Summary

### Glue role permissions
| Permission | On | Why |
|---|---|---|
| `AWSGlueServiceRole` (managed) | Glue APIs + CloudWatch | Lets Glue run crawls and write logs |
| `s3:GetObject`, `s3:ListBucket` | CUR bucket only | Reads Parquet files to build the schema |

### Lambda role permissions
| Permission | On | Why |
|---|---|---|
| `AWSLambdaBasicExecutionRole` (managed) | CloudWatch Logs | Writes function logs |
| `athena:StartQueryExecution` etc. | Athena workgroup ARN only | Runs and reads queries — scoped to this workgroup, not all of Athena |
| `glue:GetTable`, `glue:GetDatabase`, `glue:GetPartitions` | `*` | Athena needs to look up table schema from Glue catalog at query time |
| `s3:GetObject`, `s3:ListBucket` | CUR bucket only | Athena reads Parquet files from here |
| `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject` | Results bucket only | Athena writes results here; Lambda reads them back |
| `ec2:DescribeVolumes`, `ec2:DescribeInstances`, `ec2:DescribeSnapshots` | `*` | Powers the Volume Inventory tab — shows current attachment state |

---

## In One Sentence Per Layer

| Layer | One sentence |
|---|---|
| **S3 (CUR bucket)** | Holds the billing data — the single source of truth for all EBS costs across all accounts |
| **S3 (results bucket)** | Athena's scratch space — every SQL query writes its output here before Lambda reads it |
| **Glue** | Reads the Parquet files and tells Athena what columns exist so SQL queries can run |
| **Athena** | Executes the SQL that aggregates monthly EBS spend and calculates savings |
| **Lambda** | Middleman — triggers Athena, waits for results, formats everything as JSON for the dashboard |
| **API Gateway** | Gives the React dashboard a public HTTPS URL to call, with CORS configured |

---

## Key Facts to Remember

- CUR API is **always us-east-1** regardless of where your resources live
- Athena **always needs an S3 results bucket** — it cannot return results in-memory
- Glue crawler must be **run at least once** before Athena can query the data
- `force_destroy = true` on both S3 buckets means `terraform destroy` cleans up everything including files
- The 1 GB Athena scan cap protects against accidental expensive queries in your personal account — raise it for production
- All resources are tagged `Project = ebs-dash-test` so you can find and audit them easily in Cost Explorer

---

## How to Run the Test

```bash
# 1. Deploy all 21 resources (~3 min)
cd infra/test
terraform init
terraform apply

# 2. Install Python deps
pip install pyarrow pandas boto3

# 3. Generate synthetic data + upload to S3
python generate_mock_cur.py --upload --bucket $(terraform output -raw cur_bucket)

# 4. Run the Glue crawler to register the table in Athena
aws glue start-crawler --name $(terraform output -raw crawler_name)
# Wait ~1 min then check:
aws glue get-crawler --name $(terraform output -raw crawler_name) --query 'Crawler.State'

# 5. Point the dashboard at the real API
echo "VITE_USE_MOCK=false" > ../../.env.local
echo "VITE_API_URL=$(terraform output -raw api_url)" >> ../../.env.local

# 6. Start the dashboard
cd ../../ && npm run dev

# 7. Tear everything down when done (~$0.05 total cost)
cd infra/test && terraform destroy
```
