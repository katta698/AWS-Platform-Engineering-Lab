# AWS Platform Engineering Lab

**52-week hands-on AWS lab series — building production-grade cloud infrastructure from scratch.**

> 14 years as a DBA → transitioning to Cloud Architecture.
> Every week: real code, real bugs, real fixes. No tutorials. No sandboxes.

---

## Full 52-Week Roadmap

### Phase 1 — Self-Service Platforms (Weeks 1–8)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| [Week 01](./week-01-enterprise-ec2-provisioning) | Enterprise EC2 Self-Service | VPC, EC2, ASG, ALB, Lambda, Step Functions, API Gateway, ServiceNow | ✅ Complete |
| [Week 02](./week-02-aurora-self-service) | Aurora Self-Service Database Platform | Aurora Serverless v2, Secrets Manager, Lambda, Step Functions | ✅ Complete |
| Week 03 | Fleet Management + Patch Automation | SSM Fleet Manager, Patch Manager, Run Command, Inventory, ServiceNow | 🔜 Next |
| Week 04 | S3 Intelligent Storage Platform | S3 Intelligent-Tiering, Lifecycle Policies, Cost Automation | 📅 Planned |
| Week 05 | Account Vending Machine | AWS Organizations, Control Tower, Account Factory, SCPs | 📅 Planned |
| Week 06 | IAM Identity Center (SSO) | IAM Identity Center, Permission Sets, ServiceNow Access Requests | 📅 Planned |
| Week 07 | Cost Anomaly Detection + Auto-Remediation | Cost Explorer, Anomaly Detection, EventBridge, Lambda | 📅 Planned |
| Week 08 | ECS Fargate Self-Service | ECS Fargate, ECR, ALB, Task Definitions, ServiceNow | 📅 Planned |

### Phase 2 — Observability & Security (Weeks 9–16)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| Week 09 | Centralised Logging Platform | CloudWatch cross-account, OpenSearch, Log Aggregation | 📅 Planned |
| Week 10 | Security Hub + GuardDuty Automation | Security Hub, GuardDuty, EventBridge, Lambda auto-remediation | 📅 Planned |
| Week 11 | AWS Config Compliance Automation | Config Rules, Auto-Remediation, Compliance Dashboard | 📅 Planned |
| Week 12 | WAF + Shield Standard | WAF Web ACL, Rate Limiting, DDoS Protection, Managed Rules | 📅 Planned |
| Week 13 | VPC Flow Logs + Network Intelligence | Flow Logs, Athena, traffic analysis, anomaly detection | 📅 Planned |
| Week 14 | CloudTrail Lake + Audit Automation | CloudTrail Lake, SIEM integration, Query Editor | 📅 Planned |
| Week 15 | Secrets Rotation at Scale | Cross-account rotation, rotation orchestration, break-glass access | 📅 Planned |
| Week 16 | Private CA + Certificate Automation | ACM Private CA, internal PKI, auto-renewal pipeline | 📅 Planned |

### Phase 3 — Containers & Modern Patterns (Weeks 17–24)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| Week 17 | EKS Cluster Self-Service | EKS, IRSA, namespace isolation, developer onboarding | 📅 Planned |
| Week 18 | GitOps with ArgoCD on EKS | ArgoCD, app-of-apps, progressive delivery, drift detection | 📅 Planned |
| Week 19 | EventBridge Event-Driven Platform | EventBridge, event buses, schema registry, cross-account events | 📅 Planned |
| Week 20 | Blue/Green Deployment Automation | CodeDeploy, traffic shifting, automated rollback | 📅 Planned |
| Week 21 | Container Image Security Pipeline | ECR scanning, image signing, policy enforcement | 📅 Planned |
| Week 22 | Service Mesh with App Mesh | Traffic management, observability, mTLS between services | 📅 Planned |
| Week 23 | Chaos Engineering Platform | FIS fault injection, resilience testing, runbooks | 📅 Planned |
| Week 24 | Serverless Microservices | API Gateway + Lambda, DynamoDB, SAM, local testing | 📅 Planned |

### Phase 4 — Data & Database (Weeks 25–32)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| Week 25 | DynamoDB Self-Service Platform | DynamoDB, DAX, on-demand capacity, table-per-tenant | 📅 Planned |
| Week 26 | ElastiCache Redis Cluster | ElastiCache, Redis, caching layer, automated failover | 📅 Planned |
| Week 27 | RDS Multi-Region with Read Replicas | RDS, read replicas, global database pattern, failover automation | 📅 Planned |
| Week 28 | Database Migration Service | DMS, homogeneous + heterogeneous migrations, CDC, cutover | 📅 Planned |
| Week 29 | Redshift Data Warehouse | Redshift Serverless, data sharing, Spectrum, RA3 | 📅 Planned |
| Week 30 | Lake Formation + Data Catalog | Lake Formation, Glue, fine-grained access, self-service data lake | 📅 Planned |
| Week 31 | Kinesis Data Streaming Platform | Kinesis, Firehose, Lambda consumer, S3 sink | 📅 Planned |
| Week 32 | MSK Managed Kafka | MSK, consumer groups, Schema Registry, event streaming | 📅 Planned |

### Phase 5 — Networking & Multi-Account (Weeks 33–40)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| Week 33 | Transit Gateway Hub-Spoke | Transit Gateway, route tables, shared services VPC | 📅 Planned |
| Week 34 | PrivateLink + Endpoint Services | PrivateLink, cross-account access, private SaaS exposure | 📅 Planned |
| Week 35 | Route 53 DNS Automation | Route 53, intelligent routing, health checks, private zones | 📅 Planned |
| Week 36 | Network Firewall + Centralised Egress | Network Firewall, inspection VPC, stateful rules, domain filtering | 📅 Planned |
| Week 37 | Global Accelerator | Global Accelerator, anycast, latency-based routing | 📅 Planned |
| Week 38 | Multi-Region Active-Active | Route 53 health checks, global resilience, data replication | 📅 Planned |
| Week 39 | Disaster Recovery Automation | Elastic DR, RTO/RPO automation, failover runbooks | 📅 Planned |
| Week 40 | AWS Backup at Enterprise Scale | AWS Backup, cross-region, compliance reports | 📅 Planned |

### Phase 6 — AI, FinOps & Capstone (Weeks 41–52)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| Week 41 | Bedrock AI-Powered Self-Service | Bedrock, RAG, natural language infra requests, Lambda | 📅 Planned |
| Week 42 | SageMaker ML Pipeline | SageMaker, model registry, endpoint automation, CI/CD | 📅 Planned |
| Week 43 | FinOps Intelligence Dashboard | Cost Intelligence Dashboard, showback, chargeback, tagging | 📅 Planned |
| Week 44 | Well-Architected Review Automation | WA Tool API, automated checks, remediation tracking | 📅 Planned |
| Week 45 | Service Control Policies at Scale | SCPs, guardrails, permission boundaries, deny-list patterns | 📅 Planned |
| Week 46 | Lambda Power Tuning + Optimisation | Memory tuning, cold start reduction, provisioned concurrency | 📅 Planned |
| Week 47 | CodePipeline Enterprise CI/CD | Multi-stage pipeline, approval gates, cross-account deploy | 📅 Planned |
| Week 48 | CloudFormation StackSets | Multi-account/multi-region baseline, drift detection | 📅 Planned |
| Week 49 | Internal Developer Portal | Backstage on ECS, service catalog, tech radar, TechDocs | 📅 Planned |
| Week 50 | Step Functions Express Workflows | High-volume event processing, saga pattern, compensations | 📅 Planned |
| Week 51 | Platform Reliability Engineering | SLOs, error budgets, automated incident response | 📅 Planned |
| Week 52 | Capstone: Full Cloud Platform | Everything integrated — self-service, GitOps, AI, FinOps, DR | 📅 Planned |

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

**Resources:** 74 Terraform resources | **Blog:** https://blog.jayanthkatta.com/2026/05/week-1-from-ticket-to-ec2-in-6-minutes.html

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

**Resources:** 67 Terraform resources | **Blog:** https://blog.jayanthkatta.com/2026/05/week-2-automating-postgresql.html

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

## GitHub Actions Workflows

All workflows live at repo root `.github/workflows/` (GitHub only reads from this location):

| Workflow | Trigger | Purpose |
|---|---|---|
| `week-01-deploy.yml` | `workflow_dispatch` / `repository_dispatch` | Deploy Week 1 EC2 infrastructure |
| `week-01-destroy.yml` | `workflow_dispatch` (manual only) | Destroy Week 1 — requires typing `DESTROY` |
| `week-02-deploy.yml` | `workflow_dispatch` / `repository_dispatch` | Deploy Week 2 Aurora infrastructure |
| `week-02-destroy.yml` | `workflow_dispatch` (manual only) | Destroy Week 2 — requires typing `DESTROY` + ticket ID |

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

---

## About

Jay Katta — 14 years as a DBA, transitioning to Cloud Architecture.
Building one production-grade AWS pattern every week for 52 weeks.

- GitHub: [@katta698](https://github.com/katta698)
- Blog: https://blog.jayanthkatta.com
