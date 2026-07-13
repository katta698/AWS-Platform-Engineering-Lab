# EBS Savings Dashboard — Work Deployment Prerequisites

Complete checklist before pushing this project to your work environment (400+ accounts, HCP Terraform).
Go through every section and confirm each item before running terraform apply.

---

## 1. People & Approvals

| Item | Details | Confirmed |
|---|---|---|
| Team/manager approval | Get sign-off to deploy a new dashboard in Security Tooling account | [ ] |
| Security review | Share this repo with your security team — Lambda cross-account roles need approval | [ ] |
| Cloud platform team | Confirm which account to deploy to (Security Tooling recommended) | [ ] |
| Cost approval | Athena, Lambda, API GW, CloudFront, WAF have small ongoing costs | [ ] |
| Change management | Does your org require a change ticket for new infra deployments? | [ ] |

---

## 2. AWS Account Prerequisites

### 2a. Which account to deploy to
```
Recommended: Security Tooling account
Reason:      Central visibility account, not subject to workload SCPs,
             already has cross-account trust patterns established

NOT: Management/payer account
Reason: SCPs don't apply there but it is high-risk — avoid deploying
        workloads in the management account
```

### 2b. CUR / AWS Data Exports (most critical)
```
[ ] AWS Data Export (CUR 2.0) is already configured in your management account
[ ] CUR data is landing in an S3 bucket — get the bucket name and path
[ ] Glue crawler already exists OR you have permission to create one
[ ] Know your Glue database name and table name:
      aws glue get-tables --database-name <db> --query 'TableList[].Name'
[ ] Athena workgroup already exists OR you have permission to create one
[ ] CUR data covers at least 3 months of history for meaningful trend charts
[ ] If CUR is less than 3 months old — raise a support ticket for 36-month backfill
```

### 2c. AWS Organizations
```
[ ] Know your Organization ID:
      aws organizations describe-organization --query 'Organization.Id' --output text
[ ] Know your management account ID (payer account)
[ ] Have a list of all active member account IDs:
      aws organizations list-accounts --query 'Accounts[?Status==`ACTIVE`].Id' --output text
[ ] Understand your OU structure (which OU is Security Tooling under?)
```

### 2d. Existing infrastructure to reuse
```
[ ] Does a Glue crawler for CUR already exist? → reuse it, don't create a new one
[ ] Does an Athena workgroup already exist? → reuse it, set CUR_TABLE + ATHENA_WORKGROUP vars
[ ] Does an S3 results bucket already exist? → reuse it
[ ] Is there already a Lambda execution role with Athena access? → reuse it
```

---

## 3. IAM & Access Prerequisites

### 3a. Your personal access to deploy
```
[ ] You have SSO access to the Security Tooling account
[ ] Your permission set includes:
      - IAM (create roles, policies, attach policies)
      - Lambda (create, update, invoke)
      - S3 (create buckets, put objects, lifecycle rules)
      - Glue (create database, crawler, get tables)
      - Athena (create workgroup, start queries)
      - API Gateway (create APIs, integrations, routes)
      - CloudWatch (create log groups)
      - STS (AssumeRole — for Phase 2)
      - Organizations read (for Phase 2)
[ ] If Engineers permission set is too restrictive → request temporary BreakGlassAdmins
    for initial deployment, then downgrade back to Engineers
```

### 3b. HCP Terraform execution role
```
[ ] HCP Terraform OIDC provider exists in Security Tooling account:
      aws iam list-open-id-connect-providers | grep terraform
[ ] HCPTerraformRole exists with correct trust policy for app.terraform.io
[ ] HCPTerraformRole has these permissions:
      - All of 3a above (same as your personal access)
      - sts:AssumeRole on arn:aws:iam::*:role/EBSDashboardReadRole (Phase 2)
[ ] HCP Terraform workspace is configured to use OIDC dynamic credentials
    (no static AWS keys stored in HCP Terraform variables)
```

### 3c. Lambda execution role
```
[ ] Terraform will create this automatically
[ ] Make sure your IAM permission set allows iam:CreateRole and iam:PutRolePolicy
[ ] If IAM permissions are restricted by SCP — check with platform team
```

### 3d. EBSDashboardReadRole in member accounts (Phase 2 only)
```
[ ] Decision made on deployment method:
      Option A: Terraform Stacks (HCP Terraform Plus tier)
      Option B: generate_providers.py script (Free/Standard tier)
[ ] If Option B: HCP Terraform workspace created for cross_account_roles/
[ ] Execution role in each member account exists (TerraformExecutionRole or
    OrganizationAccountAccessRole or AWSControlTowerExecution)
[ ] Ask platform team: "What role does Terraform assume in member accounts?"
```

---

## 4. Tool Installations (your laptop)

```bash
# Check each tool is installed and version is correct

# AWS CLI v2 (not v1)
aws --version
# Expected: aws-cli/2.x.x

# Terraform >= 1.10.0 (required for use_lockfile = true)
terraform --version
# Expected: Terraform v1.10.x or higher

# Python 3.10+ (for generate_mock_cur.py and generate_providers.py)
python --version
# Expected: Python 3.10.x or higher

# Python packages for mock CUR data generation
pip install pyarrow pandas boto3

# Node.js 18+ (for React frontend)
node --version
# Expected: v18.x.x or higher

# npm
npm --version

# Git
git --version

# Install frontend dependencies
cd ebs-savings-dashboard
npm install
```

---

## 5. HCP Terraform Prerequisites

```
[ ] HCP Terraform account exists (app.terraform.io)
[ ] Organization created in HCP Terraform
[ ] Workspace created for this project:
      Recommended name: ebs-savings-dashboard-phase1
[ ] Workspace execution mode: Remote (not Local)
[ ] AWS OIDC dynamic credentials configured in workspace:
      Settings → Provider Authentication → AWS
      Role ARN: arn:aws:iam::<security-tooling-account>:role/HCPTerraformRole
[ ] Workspace variables set:
      TF_VAR_aws_region  = us-east-1
      TF_VAR_prefix      = <your-prefix>  (e.g. "ebsdash")
      TF_VAR_cur_table   = <glue-table-name>
[ ] VCS connection: repo connected to HCP Terraform workspace
[ ] Terraform version set to >= 1.10.0 in workspace settings
[ ] State backend configured (HCP Terraform manages state — no S3 backend needed)
```

---

## 6. Network & DNS Prerequisites (Production only)

```
[ ] Custom domain available? (e.g. ebs-dashboard.yourcompany.com)
[ ] If yes:
      [ ] ACM certificate requested in us-east-1 (required for CloudFront)
      [ ] Certificate is VALIDATED (DNS or email validation complete)
      [ ] Route53 hosted zone exists OR DNS team ready to add CNAME
[ ] If no custom domain:
      [ ] Use CloudFront default domain (*.cloudfront.net) — no cert needed
```

---

## 7. Security Prerequisites

```
[ ] WAF enabled in us-east-1 (required for CloudFront WAF)
[ ] KMS key policy reviewed — Lambda role needs kms:Decrypt access
[ ] Cognito user pool planned (for JWT auth on API Gateway)
[ ] CloudTrail enabled in Security Tooling account (for audit logging)
[ ] S3 bucket policies reviewed — no public access
[ ] VPC not required (Lambda uses public endpoints) — confirm with security team
[ ] Data classification: CUR data contains cost info — confirm it's OK in Security Tooling S3
```

---

## 8. Code Changes Required for Work

These are the specific values you must update before deploying at work:

### infra/phase1/main.tf (or production main.tf)
```hcl
# Change these values:
variable "prefix" { default = "ebsdash" }        # your org prefix
variable "aws_region" { default = "us-east-1" }  # your region

# Lambda environment variables:
ATHENA_DATABASE  = "<your-existing-glue-database>"
ATHENA_WORKGROUP = "<your-existing-workgroup>"
RESULTS_BUCKET   = "<your-existing-results-bucket>"  # or let Terraform create one
CUR_TABLE        = "<your-glue-table-name>"           # from aws glue get-tables
```

### infra/phase2/main.tf
```hcl
variable "member_role_name" { default = "EBSDashboardReadRole" }
variable "org_id"           { default = "o-9m6v3kzg5a" }        # your org ID
```

### Frontend .env.local (or environment variable in CI)
```
VITE_API_URL=https://<your-api-gateway-or-cloudfront-url>/
VITE_USE_MOCK=false
```

---

## 9. Pre-deployment Verification Commands

Run these BEFORE terraform apply to confirm your access is correct:

```bash
# 1. Confirm you're in the right account
aws sts get-caller-identity --profile <your-work-profile>
# Expected: Security Tooling account ID

# 2. Confirm CUR table exists in Glue
aws glue get-tables \
  --database-name <cur-database> \
  --query 'TableList[].Name' \
  --profile <your-work-profile>

# 3. Confirm Athena workgroup exists
aws athena list-work-groups \
  --query 'WorkGroups[].Name' \
  --profile <your-work-profile>

# 4. Confirm Organization ID
aws organizations describe-organization \
  --query 'Organization.Id' \
  --output text \
  --profile <your-work-profile>

# 5. Confirm member accounts list
aws organizations list-accounts \
  --query 'Accounts[?Status==`ACTIVE`].[Id,Name]' \
  --output table \
  --profile <your-work-profile>

# 6. Terraform plan (no changes, just verify)
cd infra/phase1
terraform init
terraform plan
# Review plan output — confirm only expected resources are created
```

---

## 10. Phase Deployment Order

Follow this exact order — do not skip steps:

```
Step 1: Confirm CUR data exists and Glue table is queryable in Athena
         → Run a manual Athena query first to confirm data is there

Step 2: Deploy Phase 1 (CUR only)
         cd infra/phase1
         terraform apply
         → Test all 4 cost tabs in dashboard

Step 3: Validate Phase 1 for 1-2 weeks
         → Get feedback from stakeholders
         → Confirm numbers match expectations

Step 4: Deploy cross-account roles (Phase 2 prereq)
         cd infra/cross_account_roles
         python generate_providers.py ...
         terraform apply

Step 5: Deploy Phase 2 (adds Volume Inventory tab)
         cd infra/phase2
         terraform apply

Step 6: Production hardening
         → Add CloudFront + WAF + KMS + Cognito
         → Add custom domain
         → Enable MFA on Cognito user pool
```

---

## 11. Questions to Ask Your Platform Team

Before starting, get answers to these:

```
1. Which account should I deploy the EBS dashboard to?
   (Recommend: Security Tooling)

2. What is the name of the Glue database and table for CUR data?

3. Does an Athena workgroup already exist for cost queries?

4. What role does HCP Terraform assume in member accounts?
   (TerraformExecutionRole / OrganizationAccountAccessRole / AWSControlTowerExecution)

5. What is the HCP Terraform organization name and workspace naming convention?

6. Is there an existing OIDC provider for HCP Terraform in the Security Tooling account?

7. Does your org use Terraform Stacks (Plus tier) or standard workspaces?

8. What SCP restrictions apply to the Security Tooling account?
   (Specifically: are IAM role creation and STS AssumeRole allowed?)

9. Is there a change management process for new Lambda + API Gateway deployments?

10. Who needs to approve cross-account IAM role creation in member accounts?
    (EBSDashboardReadRole needs to be deployed to 400+ accounts)
```

---

## Summary Checklist

```
[ ] Approvals obtained
[ ] Target account identified (Security Tooling)
[ ] CUR data confirmed queryable in Athena
[ ] Glue table name confirmed
[ ] Organization ID noted
[ ] Your SSO access confirmed for target account
[ ] HCP Terraform workspace created + OIDC configured
[ ] All tools installed (AWS CLI v2, Terraform 1.10+, Python 3.10+, Node 18+)
[ ] Code values updated (prefix, database, table, workgroup names)
[ ] Platform team questions answered
[ ] terraform plan reviewed (no surprises)
[ ] Phase deployment order understood
```

When every box above is checked — you are ready to deploy.
