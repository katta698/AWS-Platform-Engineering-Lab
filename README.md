# AWS Platform Engineering Lab

**52-week hands-on AWS lab series — building production-grade cloud infrastructure from scratch.**

> 14 years as a DBA → transitioning to Cloud Architecture.
> Every week: real code, real bugs, real fixes. No tutorials. No sandboxes.

---

## Lab Structure

Each week lives in its own folder with full Terraform code, Lambda functions,
GitHub Actions workflows, scripts, and a blog post.

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| [Week 01](./week-01-enterprise-ec2-provisioning) | Enterprise EC2 Self-Service | VPC, EC2, ASG, ALB, Lambda, Step Functions, API Gateway, ServiceNow | ✅ Complete |
| [Week 02](./week-02-aurora-self-service) | Aurora Self-Service Database Platform | Aurora Serverless v2, Secrets Manager, Lambda, Step Functions, API Gateway | ✅ Complete |
| Week 03 | *(coming soon)* | | 🔜 |

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

**Resources:** 74 Terraform resources

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

**Resources:** 67 Terraform resources

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

## Blog & LinkedIn

Each week includes a full blog post and LinkedIn write-up:

- Week 01 blog: https://blog.jayanthkatta.com/2026/05/week-1-from-ticket-to-ec2-in-6-minutes.html
- Week 02 blog: *(publish pending — HTML ready in week-02-aurora-self-service/blog/)*

---

## About

Jay Katta — 14 years as a DBA, transitioning to Cloud Architecture.
Building one production-grade AWS pattern every week for 52 weeks.

- GitHub: [@katta698](https://github.com/katta698)
- Blog: https://blog.jayanthkatta.com
