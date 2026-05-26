# Week 2: Aurora Self-Service Database Platform

**52-Week AWS Platform Engineering Lab — Week 2 of 52**

A self-service platform where developers submit a ServiceNow ticket and get a
fully isolated PostgreSQL database — with dedicated credentials, Secrets Manager
auto-rotation, and zero DBA involvement.

## Architecture

```
ServiceNow Ticket
      │
      ▼
API Gateway POST /provision
      │
      ▼
Lambda: webhook_receiver  (validates HMAC, starts Step Functions)
      │
      ▼
Step Functions State Machine
      │
      ├─► Lambda: db_provisioner
      │     ├── Connects to Aurora (via master secret)
      │     ├── CREATE DATABASE {db_name}
      │     ├── CREATE USER {db_name}_user
      │     ├── GRANT ALL PRIVILEGES
      │     ├── Stores secret: /{project}/{env}/db/{db_name}
      │     └── Enables 30-day auto-rotation
      │
      └─► Lambda: status_updater
            └── Closes ServiceNow ticket with connection details

Aurora Serverless v2 (PostgreSQL 16)
  Writer: selfservice-db-dev-aurora.cluster-xxxxx.us-east-1.rds.amazonaws.com
  Reader: selfservice-db-dev-aurora.cluster-ro-xxxxx.us-east-1.rds.amazonaws.com
  Scaling: 0.5 → 16 ACUs (auto, based on load)
```

## Multi-Tenant Design

| Concern        | Approach                                      |
|----------------|-----------------------------------------------|
| Isolation       | PostgreSQL database-per-tenant               |
| Credentials     | Dedicated user per database                  |
| Secret storage  | Secrets Manager: `/{project}/{env}/db/{name}`|
| Rotation        | 30-day auto-rotation per secret               |
| Scale limit     | None — Aurora Serverless v2 scales to demand |
| Connection limit| 50 connections per tenant (configurable)      |

## Quick Start

### Prerequisites
- AWS CLI configured with admin permissions
- Terraform >= 1.7
- Python 3.12 (for Lambda layer build)
- ServiceNow developer instance

### Step 1 — Build the pg8000 Lambda Layer
```bash
cd week-02-aurora-self-service
sh scripts/build_layer.sh
# Outputs: pg8000_layer_arn — copy this into terraform.tfvars
```

### Step 2 — Configure tfvars
```bash
cp terraform/environments/dev/terraform.tfvars.example \
   terraform/environments/dev/terraform.tfvars
# Edit terraform.tfvars with your values
```

### Step 3 — Deploy
```bash
sh scripts/deploy.sh
```
Aurora cluster takes ~10 minutes to become available.

### Step 4 — Test provisioning manually
```bash
# Get your API URL from Terraform output
API_URL=$(cd terraform/environments/dev && terraform output -raw api_gateway_url)

curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -d '{
    "ticket_id": "RITM0010001",
    "db_name":   "my_app_db",
    "team":      "platform-engineering",
    "requested_by": "jay.katta"
  }'
```

### Step 5 — Retrieve credentials
```bash
aws secretsmanager get-secret-value \
  --secret-id /selfservice-db/dev/db/my_app_db \
  --query SecretString --output text | python -m json.tool
```

### Step 6 — Connect to your database
```bash
# Get connection details from secret
export MSYS_NO_PATHCONV=1
SECRET=$(aws secretsmanager get-secret-value --secret-id /selfservice-db/dev/db/myapp_db --query SecretString --output text)

HOST=$(echo "$SECRET" | py -3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('host'))")
USER=$(echo "$SECRET" | py -3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('username'))")
DB=$(echo "$SECRET" | py -3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('dbname'))")

echo "HOST=$HOST"
echo "USER=$USER"
echo "DB=$DB"

psql -h $HOST -U $USER -d $DB
```

### Step 7 — Wire ServiceNow to API Gateway

After deploy, grab your API URL:
```bash
cd terraform/environments/dev
terraform output api_gateway_url
```

In your ServiceNow developer instance:

**Create Outbound REST Message:**
1. Search → "Outbound REST Message" → New
2. Name: `AWS DB Provisioning`
3. Endpoint: `<your api_gateway_url>` (e.g. `https://xxxx.execute-api.us-east-1.amazonaws.com/dev/provision`)
4. Save
5. Under HTTP Methods → New
6. Name: `provision`, HTTP Method: `POST`
7. Content-Type header: `application/json`
8. HTTP Request Body:
```json
{
  "ticket_id": "${ticket_number}",
  "db_name": "${db_name}",
  "team": "${team}",
  "requested_by": "${requested_by}"
}
```
9. Save

**Create Business Rule:**
1. Search → "Business Rules" → New
2. Name: `Trigger DB Provisioning`
3. Table: `sc_req_item` (RITM)
4. When: `after`, Insert: `true`, Update: `false`
5. Condition: `current.cat_item.name == 'Request Database'`
6. Script:
```javascript
(function executeRule(current, previous) {
  try {
    var r = new sn_ws.RESTMessageV2('AWS DB Provisioning', 'provision');
    r.setStringParameterNoEscape('ticket_number', current.number);
    r.setStringParameterNoEscape('db_name', current.variables.db_name.toString());
    r.setStringParameterNoEscape('team', current.variables.team.toString());
    r.setStringParameterNoEscape('requested_by', current.opened_by.user_name);
    var response = r.execute();
    gs.info('DB provisioning triggered: ' + response.getStatusCode());
  } catch(ex) {
    gs.error('DB provisioning failed: ' + ex.message);
  }
})(current, previous);
```
7. Save

### Step 8 — Set up GitHub Actions

```bash
# Create the GitHub repo first
gh repo create week-02-aurora-self-service --public

# Push code
git init
git add .
git commit -m "Week 2: Aurora self-service database platform"
git remote add origin https://github.com/katta698/week-02-aurora-self-service.git
git push -u origin main

# Add all required secrets
gh secret set AWS_ROLE_ARN          --body "arn:aws:iam::684346483786:role/github-actions-role"
gh secret set AWS_ACCOUNT_ID        --body "684346483786"
gh secret set AURORA_MASTER_PASSWORD --body "your_master_password"
gh secret set ALERT_EMAIL           --body "katta.jayant@gmail.com"
gh secret set PG8000_LAYER_ARN      --body "arn:aws:lambda:us-east-1:684346483786:layer:pg8000-python12:1"
gh secret set SERVICENOW_INSTANCE_URL --body "https://devXXXXX.service-now.com"
gh secret set SERVICENOW_USERNAME   --body "admin"
gh secret set SERVICENOW_PASSWORD   --body "your_sn_password"
gh secret set WEBHOOK_SECRET        --body "your_webhook_secret"
gh secret set GH_TOKEN_PAT          --body "ghp_your_token"
gh secret set TF_STATE_BUCKET       --body "jay-terraformstate-bucket"
```

### Step 9 — End-to-End Test via ServiceNow

1. In ServiceNow → Service Catalog → find "Request Database"
2. Fill in: Database Name, Team, Purpose
3. Submit
4. Watch **Step Functions console** → new execution starts
5. After ~2 min → execution completes
6. Check Secrets Manager: `/selfservice-db/dev/db/<your_db_name>` created
7. ServiceNow ticket closed with connection details

### Cleanup
```bash
sh scripts/cleanup.sh
# Destroys all infrastructure, deletes log groups
# Aurora takes ~5 min to fully delete
```

## Cost

| Resource                       | Cost/month (if left running) |
|--------------------------------|------------------------------|
| Aurora Serverless v2 (0.5 ACU) | ~$43                         |
| NAT Gateway                    | ~$32                         |
| Lambda (minimal traffic)       | ~$0                          |
| Secrets Manager (per secret)   | ~$0.40/secret                |
| **Total**                      | **~$75/month**               |
| **Destroyed between sessions** | **$0**                       |

## GitHub Secrets Required

| Secret                  | Description                          |
|-------------------------|--------------------------------------|
| `AWS_ROLE_ARN`          | IAM role for OIDC (from Week 1)      |
| `AWS_ACCOUNT_ID`        | Your 12-digit AWS account ID         |
| `AURORA_MASTER_PASSWORD`| Strong password for Aurora admin     |
| `ALERT_EMAIL`           | Email for CloudWatch alarm SNS       |
| `PG8000_LAYER_ARN`      | Output from build_layer.sh           |
| `SERVICENOW_INSTANCE_URL` | https://devXXXXX.service-now.com   |
| `SERVICENOW_USERNAME`   | ServiceNow admin username            |
| `SERVICENOW_PASSWORD`   | ServiceNow admin password            |
| `WEBHOOK_SECRET`        | HMAC signing secret                  |
| `GH_TOKEN_PAT`          | GitHub PAT (repo scope)              |

## Security Patterns

- **No public database access** — Aurora lives in isolated subnets with no internet route
- **Least-privilege** — Lambda role scoped to specific secret ARN prefixes only
- **Secrets Manager rotation** — every tenant database rotates independently on a 30-day schedule
- **Zero-downtime rotation** — 4-step protocol: createSecret → setSecret → testSecret → finishSecret
- **HMAC-signed webhooks** — ServiceNow payload validated before execution starts
- **OIDC for CI/CD** — no long-lived AWS credentials in GitHub

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `could not connect to server` | Lambda can't reach Aurora | Check Lambda SG has access to Aurora SG on port 5432 |
| `pg8000 module not found` | Layer not attached | Verify `pg8000_layer_arn` in tfvars matches published layer |
| `password authentication failed` | Master secret stale | `aws secretsmanager get-secret-value --secret-id /selfservice-db/dev/aurora/master` |
| `ResourceAlreadyExistsException` | Log group survived destroy | Run `sh scripts/deploy.sh` — pre-flight cleans it |
| `ExecutionAlreadyExists` | Duplicate ticket submission | Idempotent — webhook_receiver handles this gracefully |
| Aurora not available after apply | Cold start takes ~10 min | Wait and retry — Serverless v2 writer needs time to provision |
