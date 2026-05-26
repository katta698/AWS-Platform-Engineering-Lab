# Week 1 — Enterprise Self-Service EC2 Provisioning

**Theme:** Enterprise Self-Service Infrastructure  
**Difficulty:** ⭐⭐⭐ Intermediate-Advanced  
**Estimated Completion:** 8–12 hours  
**Business Value:** Eliminates manual provisioning, enforces standards, full audit trail

---

## A. Business Problem

Enterprise IT teams are overwhelmed with manual EC2 provisioning requests. Each request involves:
- Emailing or ticketing the cloud team
- A 2–5 day wait time
- Inconsistent configurations (different people applying different security standards)
- No cost tagging, no audit trail

**This project automates the entire workflow end-to-end**, from a ServiceNow catalog request to a fully deployed, monitored, production-grade EC2 environment — with zero manual intervention after manager approval.

---

## B. Real-World Scenario

> "A developer at Acme Corp needs a new EC2 environment for a product launch. She opens the ServiceNow catalog, selects 'EC2 Environment Request', fills in instance type, environment, and cost center. Her manager approves in ServiceNow. Within 15 minutes, she receives the ALB DNS endpoint in her ticket and the ticket closes automatically."

This mirrors exactly how Fortune 500 companies operate their cloud platforms.

---

## C. Architecture Overview

```
ServiceNow Catalog Request
    │
    ▼ (Manager Approval)
ServiceNow REST Webhook
    │
    ▼
API Gateway (POST /provision)
    │
    ▼
Lambda: Receiver (validate + parse)
    │
    ▼
Step Functions State Machine
    │
    ├─── Lambda: Status Updater → ServiceNow "In Progress"
    │
    ├─── Lambda: Deployment Trigger (waitForTaskToken)
    │         │
    │         ▼
    │    GitHub Actions (repository_dispatch)
    │         │
    │         ├── Terraform Plan
    │         ├── Terraform Apply
    │         │     └── VPC / SG / IAM / ALB / ASG / CloudWatch / SNS
    │         │
    │         └── SendTaskSuccess/Failure → Step Functions callback
    │
    └─── Lambda: Status Updater → ServiceNow "Resolved" + ALB DNS
```

---

## D. Step-by-Step Implementation Plan

### Phase 1 — AWS Foundations (2 hours)
1. Create S3 bucket for Terraform remote state with versioning + encryption
2. Create DynamoDB table `terraform-lock` for state locking
3. Create S3 bucket for ALB access logs
4. Request or import ACM certificate for your domain

### Phase 2 — IAM & OIDC (1 hour)
1. Run `terraform apply` for the IAM module first (standalone)
2. Capture the GitHub Actions role ARN
3. Add `AWS_ROLE_ARN` to GitHub repository secrets

### Phase 3 — Core Infrastructure (3 hours)
1. Set up `terraform.tfvars` (copy from `terraform.tfvars.example`)
2. Run `terraform init` in `terraform/environments/dev`
3. Run `terraform plan` — review all resources
4. Run `terraform apply`
5. Run `scripts/validate.sh dev` to confirm health

### Phase 4 — Lambda & Step Functions (2 hours)
1. Package each Lambda function: `cd lambda/servicenow_receiver && zip -r handler.zip .`
2. Deploy Lambdas (manually or via Terraform — see Lambda Terraform below)
3. Create Step Functions state machine using `step_functions/state_machine.json`
4. Add SSM parameters: ServiceNow credentials, GitHub token, webhook secret

### Phase 5 — API Gateway & ServiceNow (1 hour)
1. Create REST API Gateway with `/provision` POST resource
2. Link to Lambda receiver
3. In ServiceNow (developer instance at developer.servicenow.com):
   - Create Outbound REST Message pointing to API Gateway URL
   - Create Business Rule on approval of catalog item
   - Set webhook secret in SSM

### Phase 6 — End-to-End Test (1 hour)
1. Submit a ServiceNow catalog request
2. Approve it as manager
3. Watch Step Functions execution in console
4. Watch GitHub Actions run
5. Confirm ServiceNow ticket updates with ALB DNS

---

## E. Complete Folder Structure

```
week-01-enterprise-ec2-provisioning/
├── .github/
│   └── workflows/
│       ├── deploy.yml          # Triggered by ServiceNow webhook
│       └── destroy.yml         # Manual teardown with approval
├── architecture/               # Architecture diagrams
├── docs/
│   ├── interview-questions.md
│   ├── resume-bullets.md
│   └── blog-notes.md
├── lambda/
│   ├── servicenow_receiver/    # API Gateway webhook receiver
│   │   └── handler.py
│   ├── deployment_trigger/     # Step Functions → GitHub Actions
│   │   └── handler.py
│   └── status_updater/         # Write results back to ServiceNow
│       └── handler.py
├── scripts/
│   ├── validate.sh             # Post-deployment health checks
│   └── cleanup.sh              # Safe destroy script
├── step_functions/
│   └── state_machine.json      # ASL definition
└── terraform/
    ├── environments/
    │   └── dev/
    │       ├── main.tf         # Root module — composes all modules
    │       ├── variables.tf
    │       ├── outputs.tf
    │       └── terraform.tfvars.example
    └── modules/
        ├── vpc/                # VPC, subnets, NAT GW, flow logs
        ├── security_groups/    # ALB SG, EC2 SG, VPC endpoint SG
        ├── iam/                # EC2 role, GitHub OIDC role
        ├── alb/                # ALB, target group, HTTPS listener
        ├── asg/                # Launch template, ASG, scaling policies
        ├── cloudwatch/         # Dashboard, alarms, log groups
        └── sns/                # Alert topic + email subscriptions
```

---

## F. Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Terraform | >= 1.7 | https://terraform.io |
| AWS CLI | >= 2.x | https://aws.amazon.com/cli |
| Python | 3.11+ | https://python.org |
| GitHub CLI | latest | https://cli.github.com |

---

## G. GitHub Secrets Required

| Secret | Description |
|--------|-------------|
| `AWS_ROLE_ARN` | IAM role ARN for OIDC (output from IAM module) |
| `TF_STATE_BUCKET` | S3 bucket for Terraform state |
| `TF_LOCK_TABLE` | DynamoDB lock table name |
| `ACM_CERTIFICATE_ARN` | ACM certificate for HTTPS |
| `ACCESS_LOGS_BUCKET` | S3 bucket for ALB logs |
| `ARTIFACT_BUCKET` | S3 bucket for app artifacts |

---

## H. Validation Steps

```bash
# 1. Validate Terraform
cd terraform/environments/dev
terraform validate

# 2. Run post-deployment checks
./scripts/validate.sh dev us-east-1

# 3. Test health endpoint
curl http://<ALB_DNS>/health

# 4. Check ASG instances
aws autoscaling describe-auto-scaling-groups \
  --auto-scaling-group-names selfservice-ec2-dev-asg

# 5. Check CloudWatch dashboard
# Visit: AWS Console → CloudWatch → Dashboards → selfservice-ec2-dev

# 6. Test SNS alerting
aws cloudwatch set-alarm-state \
  --alarm-name selfservice-ec2-dev-alb-5xx-errors \
  --state-value ALARM \
  --state-reason "Manual test"
```

---

## I. Screenshots to Capture

For your portfolio / LinkedIn:

1. **ServiceNow catalog form** — EC2 request form with fields
2. **ServiceNow approval flow** — Manager approval screen
3. **Step Functions execution** — Visual workflow running
4. **GitHub Actions run** — Plan and apply steps
5. **Terraform output** — Resource creation log
6. **CloudWatch dashboard** — Metrics for ALB + ASG
7. **ServiceNow ticket closed** — With ALB DNS in work notes
8. **AWS Console — VPC diagram** — Resource map view
9. **EC2 instances** — Running with correct tags
10. **SNS subscription confirmation** — Email alert setup

---

## J. Troubleshooting Guide

### Issue: Webhook signature validation fails
**Symptoms:** 401 from API Gateway  
**Fix:** Verify `x-servicenow-signature` header format. Set `ENVIRONMENT=dev` to bypass in testing.

### Issue: Step Functions execution stuck at TriggerDeployment
**Symptoms:** `waitForTaskToken` state never progresses  
**Cause:** GitHub Actions did not call `send-task-success`  
**Fix:** Check GitHub Actions logs. Ensure `AWS_ROLE_ARN` has `states:SendTaskSuccess` permission.

### Issue: Terraform apply fails — S3 bucket not found
**Symptoms:** `NoSuchBucket` error  
**Fix:** Create the state bucket manually first: `aws s3 mb s3://your-tf-state-bucket --region us-east-1`

### Issue: EC2 instances not healthy in target group
**Symptoms:** `0 healthy targets` in ALB  
**Cause 1:** Security group not allowing ALB → EC2 on app_port  
**Cause 2:** Health check path returning non-200  
**Cause 3:** User data script failed (check `/var/log/userdata.log` via SSM)  
**Fix:** `aws ssm start-session --target <instance-id>`

### Issue: OIDC authentication fails in GitHub Actions
**Symptoms:** `Could not assume role` error  
**Fix:** Verify `github_org` and `github_repo` variables match exactly. OIDC subject is case-sensitive.

### Issue: NAT Gateway costs unexpectedly high
**Fix:** For dev/learning, set `enable_nat_gateway = false` and use VPC endpoints for SSM/S3/CW.

### Issue: ServiceNow REST API returns 401
**Fix:** Verify credentials in SSM. ServiceNow developer instances may need "Integration — REST API" role assigned to API user.

---

## K. Cleanup Steps

```bash
# 1. Run cleanup script (prompts for confirmation)
./scripts/cleanup.sh dev

# 2. Or destroy via GitHub Actions (uses destroy.yml workflow)
# Go to Actions → Destroy Infrastructure → Run workflow

# 3. Manual cleanup of resources created outside Terraform:
aws s3 rb s3://your-tf-state-bucket --force
aws dynamodb delete-table --table-name terraform-lock
```

**Estimated monthly cost if left running (dev):**
- NAT Gateway: ~$32/month
- 2x t3.medium EC2: ~$60/month
- ALB: ~$22/month
- **Total: ~$114/month → Always clean up after learning!**

---

## L. IAM Permissions Summary

| Role | Purpose | Key Permissions |
|------|---------|-----------------|
| `ec2-role` | EC2 instance role | SSM, CloudWatch, S3 read |
| `github-actions-role` | CI/CD deployments | EC2, IAM PassRole, ALB, ASG, CW, SNS |
| `vpc-flow-log-role` | VPC flow logs | CloudWatch Logs write |
| Lambda execution roles | Lambda → SF, SSM, ServiceNow | Per-function least-privilege |

All roles use **least-privilege** — no `*` on sensitive resources.

---

## M. Enterprise Best Practices Applied

1. **No SSH keys** — SSM Session Manager only
2. **IMDSv2 enforced** — `http_tokens = "required"` in launch template
3. **EBS encryption** — All volumes encrypted at rest
4. **HTTPS only** — HTTP → HTTPS redirect, TLS 1.3 policy
5. **OIDC for CI/CD** — No static AWS credentials in GitHub
6. **Remote state** — S3 + DynamoDB locking
7. **VPC flow logs** — Full network traffic audit trail
8. **Cost tags** — Every resource tagged with CostCenter + SnTicket
9. **Instance refresh** — Zero-downtime rolling deployments
10. **Deletion protection** — ALB and RDS protected in prod
