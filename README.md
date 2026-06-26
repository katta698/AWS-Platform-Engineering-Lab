# AWS Platform Engineering Lab

**53-week hands-on AWS lab series — building production-grade cloud infrastructure from scratch.**

> 14 years as a DBA → transitioning to Cloud Architecture.
> Every week: real code, real bugs, real fixes. No tutorials. No sandboxes.

---

## Full 52-Week Roadmap

### Phase 1 — Self-Service Platforms (Weeks 1–9)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| [Week 01](./week-01-enterprise-ec2-provisioning) | Enterprise EC2 Self-Service | VPC, EC2, ASG, ALB, Lambda, Step Functions, API Gateway, ServiceNow | ✅ Complete |
| [Week 02](./week-02-aurora-self-service) | Aurora Self-Service Database Platform | Aurora Serverless v2, Secrets Manager, Lambda, Step Functions | ✅ Complete |
| [Week 03](./week-03-ssm-fleet-management) | SSM Fleet Management + Patch Automation | SSM Fleet Manager, Patch Manager, Run Command, Inventory, Session Manager, Automation | ✅ Complete |
| [Week 04](./week-04-glue-fleet-intelligence) | Glue Fleet Intelligence Platform | SSM Resource Data Sync, Glue Crawler, Glue ETL, Athena, S3, Lambda, Step Functions | ✅ Complete |
| [Week 05](./week-05-cost-anomaly-detection) | Cost Anomaly Detection | Cost Explorer ML, SNS ×2, Lambda, CloudWatch, HCP Terraform | ✅ Complete |
| [Week 06](./week-06-account-vending-machine) | Account Vending Machine (simulated, no Control Tower) | AWS Organizations, SCPs, Step Functions, Lambda, API Gateway, HCP Terraform | ✅ Complete |
| [Week 07](./week-07-identity-center-sso) | IAM Identity Center SSO (multi-account permission sets) | IAM Identity Center, Identity Store, Permission Sets, AWS Organizations, HCP Terraform | ✅ Complete |
| Week 08 | S3 Intelligent Storage Platform | S3 Intelligent-Tiering, Lifecycle Policies, Cost Automation | 📅 Planned |
| Week 09 | ECS Fargate Self-Service | ECS Fargate, ECR, ALB, Task Definitions, ServiceNow | 📅 Planned |

### Phase 2 — Observability & Security (Weeks 10–17)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| Week 10 | Centralised Logging Platform | CloudWatch cross-account, OpenSearch, Log Aggregation | 📅 Planned |
| Week 11 | Security Hub + GuardDuty Automation | Security Hub, GuardDuty, EventBridge, Lambda auto-remediation | 📅 Planned |
| Week 12 | AWS Config Compliance Automation | Config Rules, Auto-Remediation, Compliance Dashboard | 📅 Planned |
| Week 13 | WAF + Shield Standard | WAF Web ACL, Rate Limiting, DDoS Protection, Managed Rules | 📅 Planned |
| Week 14 | VPC Flow Logs + Network Intelligence | Flow Logs, Athena, traffic analysis, anomaly detection | 📅 Planned |
| Week 15 | CloudTrail Lake + Audit Automation | CloudTrail Lake, SIEM integration, Query Editor | 📅 Planned |
| Week 16 | Secrets Rotation at Scale | Cross-account rotation, rotation orchestration, break-glass access | 📅 Planned |
| Week 17 | Private CA + Certificate Automation | ACM Private CA, internal PKI, auto-renewal pipeline | 📅 Planned |

### Phase 3 — Containers & Modern Patterns (Weeks 18–25)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| Week 18 | EKS Cluster Self-Service | EKS, IRSA, namespace isolation, developer onboarding | 📅 Planned |
| Week 19 | GitOps with ArgoCD on EKS | ArgoCD, app-of-apps, progressive delivery, drift detection | 📅 Planned |
| Week 20 | EventBridge Event-Driven Platform | EventBridge, event buses, schema registry, cross-account events | 📅 Planned |
| Week 21 | Blue/Green Deployment Automation | CodeDeploy, traffic shifting, automated rollback | 📅 Planned |
| Week 22 | Container Image Security Pipeline | ECR scanning, image signing, policy enforcement | 📅 Planned |
| Week 23 | Service Mesh with App Mesh | Traffic management, observability, mTLS between services | 📅 Planned |
| Week 24 | Chaos Engineering Platform | FIS fault injection, resilience testing, runbooks | 📅 Planned |
| Week 25 | Serverless Microservices | API Gateway + Lambda, DynamoDB, SAM, local testing | 📅 Planned |

### Phase 4 — Data & Database (Weeks 26–33)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| Week 26 | DynamoDB Self-Service Platform | DynamoDB, DAX, on-demand capacity, table-per-tenant | 📅 Planned |
| Week 27 | ElastiCache Redis Cluster | ElastiCache, Redis, caching layer, automated failover | 📅 Planned |
| Week 28 | RDS Multi-Region with Read Replicas | RDS, read replicas, global database pattern, failover automation | 📅 Planned |
| Week 29 | Database Migration Service | DMS, homogeneous + heterogeneous migrations, CDC, cutover | 📅 Planned |
| Week 30 | Redshift Data Warehouse | Redshift Serverless, data sharing, Spectrum, RA3 | 📅 Planned |
| Week 31 | Lake Formation + Data Catalog | Lake Formation, Glue, fine-grained access, self-service data lake | 📅 Planned |
| Week 32 | Kinesis Data Streaming Platform | Kinesis, Firehose, Lambda consumer, S3 sink | 📅 Planned |
| Week 33 | MSK Managed Kafka | MSK, consumer groups, Schema Registry, event streaming | 📅 Planned |

### Phase 5 — Networking & Multi-Account (Weeks 34–41)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| Week 34 | Transit Gateway Hub-Spoke | Transit Gateway, route tables, shared services VPC | 📅 Planned |
| Week 35 | PrivateLink + Endpoint Services | PrivateLink, cross-account access, private SaaS exposure | 📅 Planned |
| Week 36 | Route 53 DNS Automation | Route 53, intelligent routing, health checks, private zones | 📅 Planned |
| Week 37 | Network Firewall + Centralised Egress | Network Firewall, inspection VPC, stateful rules, domain filtering | 📅 Planned |
| Week 38 | Global Accelerator | Global Accelerator, anycast, latency-based routing | 📅 Planned |
| Week 39 | Multi-Region Active-Active | Route 53 health checks, global resilience, data replication | 📅 Planned |
| Week 40 | Disaster Recovery Automation | Elastic DR, RTO/RPO automation, failover runbooks | 📅 Planned |
| Week 41 | AWS Backup at Enterprise Scale | AWS Backup, cross-region, compliance reports | 📅 Planned |

### Phase 6 — AI, FinOps & Capstone (Weeks 42–53)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| Week 42 | Bedrock AI-Powered Self-Service | Bedrock, RAG, natural language infra requests, Lambda | 📅 Planned |
| Week 43 | SageMaker ML Pipeline | SageMaker, model registry, endpoint automation, CI/CD | 📅 Planned |
| Week 44 | FinOps Intelligence Dashboard | Cost Intelligence Dashboard, showback, chargeback, tagging | 📅 Planned |
| Week 45 | Well-Architected Review Automation | WA Tool API, automated checks, remediation tracking | 📅 Planned |
| Week 46 | Service Control Policies at Scale | SCPs, guardrails, permission boundaries, deny-list patterns | 📅 Planned |
| Week 47 | Lambda Power Tuning + Optimisation | Memory tuning, cold start reduction, provisioned concurrency | 📅 Planned |
| Week 48 | CodePipeline Enterprise CI/CD | Multi-stage pipeline, approval gates, cross-account deploy | 📅 Planned |
| Week 49 | CloudFormation StackSets | Multi-account/multi-region baseline, drift detection | 📅 Planned |
| Week 50 | Internal Developer Portal | Backstage on ECS, service catalog, tech radar, TechDocs | 📅 Planned |
| Week 51 | Step Functions Express Workflows | High-volume event processing, saga pattern, compensations | 📅 Planned |
| Week 52 | Platform Reliability Engineering | SLOs, error budgets, automated incident response | 📅 Planned |
| Week 53 | Capstone: Full Cloud Platform | Everything integrated — self-service, GitOps, AI, FinOps, DR | 📅 Planned |

---

## What Gets Built Each Week

Every project follows the same enterprise pattern:

- **Infrastructure as Code** — 100% Terraform, modular design
- **CI/CD** — GitHub Actions with OIDC (no static AWS credentials)
- **Security by default** — least privilege IAM, secrets in Secrets Manager, private subnets
- **Cost optimized** — destroy between sessions, rebuild in minutes
- **Real-world story** — ServiceNow integration, self-service workflows, zero manual steps

---

## Week 01 — Enterprise EC2 Self-Service

**The story:** Developer submits a ServiceNow ticket → running EC2 instance in 6 minutes. No human in the loop.

**What it builds:**
- VPC with public/private subnets across 2 AZs
- ALB + Auto Scaling Group (EC2 in private subnets, SSM only — no SSH)
- 3 Lambda functions + Step Functions state machine
- API Gateway REST API with HMAC-signed webhooks
- GitHub Actions CI/CD with OIDC federation
- CloudWatch dashboard + 4 metric alarms

**Resources:** 74 Terraform resources | **Blog:** https://jayanthkatta.com/blog/week-1-from-ticket-to-ec2-in-6-minutes-enterprise-self-servi/

---

## Week 02 — Aurora Self-Service Database Platform

**The story:** Developer submits a ServiceNow ticket → isolated PostgreSQL database with auto-rotating credentials in 12 seconds. Zero DBA involvement.

**What it builds:**
- Aurora Serverless v2 (PostgreSQL 16) — scales 0.5 → 16 ACUs
- Database-per-tenant isolation — unlimited databases on shared cluster
- Secrets Manager with 4-step zero-downtime rotation per tenant
- Lambda db_provisioner — CREATE DATABASE + user + secret in one execution
- Step Functions orchestration
- CloudWatch dashboard with Performance Insights

**Resources:** 67 Terraform resources | **Blog:** https://jayanthkatta.com/blog/week-2-automating-postgresql-provisioning-with-servicenow-an/

**End-to-end validated:**
- ServiceNow RITM submitted → Step Functions execution → database provisioned → ticket closed in **8.7 seconds**
- RDS Query Editor confirmed: `postgres`, `rdsadmin`, `selfservice`, `myapp_db`, `jay_test` databases on shared Aurora cluster
- Secrets Manager auto-rotation enabled per tenant database

**Key lessons learned:**
- `use_lockfile = true` in Terraform backend requires Terraform >= 1.10 — workflows pinned to 1.7.5 will fail at init
- GitHub OIDC trust policy `sub` condition must use `StringLike` with `:*` wildcard to cover both branch and environment-scoped workflows
- IAM role for GitHub Actions must reference the correct repo name — trust policy is case-sensitive
- pg8000 Lambda layer is built once via `build_layer.sh` and reused across deploys — the deploy workflow reads the ARN from `PG8000_LAYER_ARN` GitHub secret
- `.github/workflows/` must live at repo root — subfolders are ignored by GitHub Actions

---

## Week 03 — SSM Fleet Management + Patch Automation

**The story:** Ops engineer submits a ServiceNow ticket → EC2 fleet onboarded to SSM and patched to 100% compliance. No SSH. No manual steps.

**What it builds:**
- EC2 fleet (ASG) with SSM agent — no key pairs, no port 22 anywhere
- 7 SSM services: Fleet Manager, Patch Manager, Run Command, Session Manager, State Manager, Automation, Inventory
- Custom SSM Automation documents — onboard-instance and patch-fleet runbooks
- Patch baselines for Amazon Linux 2023 and Windows Server
- Maintenance window (weekly Sunday 02:00 UTC)
- 4 Lambda functions + Step Functions orchestration
- API Gateway with HMAC-signed ServiceNow webhooks
- Session logs to S3 + CloudWatch (90-day retention)

**End-to-end validated:**
- ServiceNow RITM → Step Functions → 3 instances patched → 100% compliance → ticket closed with report
- Manual EC2 onboarded via single ticket: tags applied, patch scan run, brought under full management
- 472 patches installed across fleet, 0 missing, 0 failed
- Session Manager shell access with full audit logging — no SSH required

**Key lessons learned:**
- AWS rejects SSM Parameter Store paths starting with `/ssm` (case-insensitive) — use `/fleet-mgmt/` prefix
- VPC endpoints not supported in all us-east-1 AZs — filter with `aws_vpc_endpoint_service` data source
- API Gateway `AWS_PROXY` URI must be `arn:aws:apigateway:{region}:lambda:path/2015-03-31/functions/{arn}/invocations`
- `CommandId` is reserved in SSM Automation outputs — rename to `PatchCommandId`
- AL2023 AMI snapshot requires minimum 30GB volume (not 20GB)
- Step Functions CloudWatch logging needs full set of log delivery permissions

**Resources:** 80+ Terraform resources | **Blog:** https://jayanthkatta.com/blog/week-3-self-service-ec2-fleet-patching-with-aws-ssm/

---

## Week 04 — Glue Fleet Intelligence Platform

**The story:** Ops engineer submits a ServiceNow ticket → SSM fleet data automatically collected, transformed, and analysed. Patch compliance and OS inventory queryable in Athena. Ticket closes itself with the results URL.

**What it builds:**
- SSM Resource Data Sync → S3 raw bucket (Bronze layer) — NDJSON per instance
- Glue Crawler — schema discovery, registers tables in Glue Data Catalog
- Glue PySpark ETL job — boto3 S3 reader (bypasses Java URI colon bug), outputs Parquet to curated bucket (Silver layer)
- Athena workgroup — SQL queries over Parquet (Gold layer)
- Step Functions polling loop — Wait → Check → Choice, self-adapting to actual job duration
- 3 Lambda functions: `webhook_receiver` (HMAC-SHA256), `glue_trigger`, `status_updater`
- API Gateway REST endpoint for ServiceNow webhook
- ServiceNow RITM auto-close with Athena console URL in close notes

**End-to-end validated:**
- ServiceNow ticket submitted → Step Functions triggered → Glue crawler ran → ETL job SUCCEEDED → Parquet in curated bucket → Athena query returned patch compliance results → ticket closed automatically
- boto3 paginator workaround confirmed: `spark.read.json()` crashes on `AWS:ComplianceSummary` paths; boto3 reads them without issue

**Key lessons learned:**
- Colons in S3 folder names (`AWS:ComplianceSummary`) break Spark/Java URI parsing — use boto3 to list and read, then `spark.createDataFrame(records)`
- API Gateway lowercases all headers — Lambda must read `x-servicenow-hmac` (lowercase), not the original casing
- SSM Resource Data Sync has a ~30 min initial delay — plan for it, add a CloudWatch alarm on the raw S3 bucket
- Step Functions polling loops need a max-iteration counter (`$.poll_count`) in production to prevent infinite loops
- ServiceNow REST API PATCH requires `sys_id` (GUID), not `number` (RITM0012345) — resolve sys_id with a GET first

**Resources:** 44 Terraform resources | **Blog:** https://jayanthkatta.com/blog/week-4-building-a-fleet-intelligence-platform-with-aws-glue-/

---

## Week 05 — Cost Anomaly Detection

**The story:** AWS bill spikes unexpectedly. A fixed budget alert would have missed it — the threshold wasn't crossed, but spending is 125% above what the ML model predicted. Cost Anomaly Detection fires the moment any service exceeds its ML baseline by $10+, Lambda formats the raw payload into a readable email, and the alert lands in your inbox within minutes.

**What it builds:**
- Cost Anomaly Monitor (DIMENSIONAL/SERVICE) — ML-based baseline across all AWS services
- SNS Topic (raw) — `costalerts.amazonaws.com` publishes the raw JSON payload here
- Lambda (`cost-alerter`) — parses the payload and formats a human-readable email
- SNS Topic (formatted alert) — Lambda publishes here; email subscriber receives the final alert
- IAM least-privilege role for Lambda (SNS:Publish + CloudWatch only)
- CloudWatch Log Group (14-day retention)
- Deployed via **HCP Terraform** (VCS-driven, org: Katta, workspace: week-05-dev) — no GitHub Actions workflow

**Resources:** 12 Terraform resources | **Blog:** https://jayanthkatta.com/blog/week-5-cost-anomaly-detection-with-aws-cost-explorer-sns-and/

---

## Week 06 — Account Vending Machine (simulated, no Control Tower)

**The story:** A team needs a new AWS account. Manually, that means a human creating the account, remembering to attach the right guardrails, and placing it in the right part of the org. A ServiceNow ticket now does all three: it creates a real AWS account, moves it into the right Organizational Unit, and the Service Control Policy attached to that OU applies the moment it lands there — no per-account setup, no follow-up ticket.

**What it builds:**
- Organizational Units (`Sandbox`, `Production`) nested under the existing `Workloads-OU`
- Service Control Policy on the `Sandbox` OU — denies large/expensive EC2 instance types and restricts activity to allowed regions
- Step Functions — orchestrates `CreateAccount` → poll → `MoveAccount` → notify ServiceNow
- Lambda (`webhook_receiver`, `account_creator`, `account_mover`, `status_notifier`) — HMAC-validated webhook, account creation/polling, OU move + tagging, ServiceNow ticket closure
- API Gateway — HTTPS endpoint for the ServiceNow webhook
- Deployed via **HCP Terraform** (VCS-driven, org: Katta, workspace: week-06-dev) — no GitHub Actions workflow
- Deliberately skips AWS Control Tower — a real managed Landing Zone is heavy and largely irreversible, not a fit for a lab account meant to be built and torn down weekly

**Resources:** 39 Terraform resources | **Blog:** https://jayanthkatta.com/blog/week-6-account-vending-machine-with-aws-organizations-and-scps/

---

## GitHub Actions Workflows

All workflows live at repo root `.github/workflows/` (GitHub only reads from this location):

| Workflow | Trigger | Purpose |
|---|---|---|
| `week-01-deploy.yml` | `workflow_dispatch` / `repository_dispatch` | Deploy Week 1 EC2 infrastructure |
| `week-01-destroy.yml` | `workflow_dispatch` (manual only) | Destroy Week 1 — requires typing `DESTROY` |
| `week-02-deploy.yml` | `workflow_dispatch` / `repository_dispatch` | Deploy Week 2 Aurora infrastructure |
| `week-02-destroy.yml` | `workflow_dispatch` (manual only) | Destroy Week 2 — requires typing `DESTROY` + ticket ID |
| `week-03-deploy.yml` | `workflow_dispatch` | Deploy Week 3 SSM Fleet Management infrastructure |
| `week-03-destroy.yml` | `workflow_dispatch` (manual only) | Destroy Week 3 — requires typing `DESTROY` |
| `week-04-deploy.yml` | `workflow_dispatch` | Deploy Week 4 Glue Fleet Intelligence infrastructure |
| `week-04-destroy.yml` | `workflow_dispatch` (manual only) | Destroy Week 4 — requires typing `DESTROY` |

All workflows use OIDC federation — no static AWS credentials stored in GitHub. IAM role: `github-actions-dev-deploy-role`.

---

## Common Patterns Across All Weeks

```
ServiceNow Ticket
      ↓
API Gateway (HTTPS endpoint)
      ↓
Lambda (HMAC validation)
      ↓
Step Functions (orchestration)
      ↓
Lambda (provisioning)
      ↓
AWS Resources created
      ↓
ServiceNow ticket closed with details
```

---

## Prerequisites (One-Time Setup)

```bash
# Required tools
aws --version          # AWS CLI v2
terraform --version    # >= 1.10 (use_lockfile support)
python --version       # Python 3.x

# AWS bootstrap (done once in Week 1)
# - S3 bucket for Terraform state: jay-terraformstate-bucket
# - GitHub OIDC provider: token.actions.githubusercontent.com
# - IAM role: github-actions-dev-deploy-role
#   Trust policy must use StringLike with repo:katta698/AWS-Platform-Engineering-Lab:*
```

---

## Cost Philosophy

All labs are designed to cost **$0 between sessions**:

```bash
# Done for the day
sh scripts/cleanup.sh   # destroys everything in ~5 min

# Back next session
sh scripts/deploy.sh    # rebuilds everything in ~10 min
```

| Week | Cost if left running | Cost destroyed |
|------|---------------------|----------------|
| 01   | ~$65/month          | $0             |
| 02   | ~$75/month          | $0             |
| 03   | ~$48/month          | $0             |
| 04   | ~$0.22/run          | $0             |
| 05   | ~$0/month (free tier) | $0           |

---

## About

Jay Katta — 14 years as a DBA, transitioning to Cloud Architecture.
Building one production-grade AWS pattern every week for 52 weeks.

- GitHub: [@katta698](https://github.com/katta698)
- Blog: https://jayanthkatta.com/blog/
