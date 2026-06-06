# Session Context — AWS Platform Engineering Lab

Paste this at the start of every new Claude session to restore full context.

---

## Who I Am

Jay Katta — 14 years as a DBA, transitioning to Cloud Architecture.
Building one production-grade AWS pattern every week for 52+ weeks.
- GitHub: @katta698
- Blog: https://blog.jayanthkatta.com
- Email: katta.jayant@gmail.com

---

## Project Location

All project files are saved here — connect this folder at the start of every session:
**C:\Users\katta\Downloads\Engineering\AWS-Infrastructure-Projects\AWS-Platform-Engineering-Lab**

---

## AWS Setup (One-Time Bootstrap — Already Done)

- AWS Region: us-east-1 (N. Virginia)
- Terraform state bucket: `jay-terraformstate-bucket`
- GitHub repo: `katta698/AWS-Platform-Engineering-Lab`
- GitHub OIDC IAM role: `github-actions-dev-deploy-role`
  - Trust policy uses `StringLike` with `repo:katta698/AWS-Platform-Engineering-Lab:*`
- Terraform version: >= 1.10 (use_lockfile support)
- pg8000 Lambda layer ARN stored in GitHub secret: `PG8000_LAYER_ARN`

---

## Command Reference Files

Every week has a `COMMANDS.md` file with all AWS CLI commands for that project.
Always refer to it for testing, validating, and operating without needing to remember syntax.

**Pattern for every week:**
- Set session variables at the top of COMMANDS.md first (`SECRET`, `API_URL`, `INSTANCE_ID` etc.)
- Simulate ServiceNow requests via curl with HMAC signature
- Change `ticket_id` to a unique RITM number each curl run — Step Functions rejects duplicate execution names
- Check Step Functions execution status to confirm success/failure
- All patch/compliance commands use `--patch-group` and `--region` flags

**Screenshots standard (Week 02 onwards):** always save to `blog/screenshots/` inside the week folder. Week 01 uses `docs/screenshots/` (already published — exception only).

**Blog files standard — every week must have:**
- `blog/screenshots/` — all screenshots with numbered filenames (e.g. `01-terraform-output.png`)
- `blog/week-XX-blog.html` — full blog post in light theme (matching Week 2 style) with screenshot placeholders
- `SCREENSHOTS.md` — filename cheat sheet at top, clean run order, detailed per-screenshot guide with filename + where + what to show
- `COMMANDS.md` — all AWS CLI commands for that week's project
- `README.md` — screenshot reminders (`📸 Screenshot: ... Save as: blog/screenshots/XX-name.png`) after every relevant step so user knows when to pause and take screenshots

**Screenshot reminder format in README (use this exact format for every week):**
```
> 📸 **Screenshot:** [what to show and where in AWS console]
> Save as: `blog/screenshots/XX-filename.png`
```

**Blog theme:** Light theme matching Week 2 — white background, blue accents, dark code blocks. Do NOT use dark theme.

**README backup rule:** Before removing screenshot reminders from README.md, always save a copy as `README-with-screenshots.md` in the same folder first. This lets you re-run the lab yourself by following the screenshot-annotated version.

**Blog publishing process (Week 03 onwards — follow this exact process every week):**
1. Take all screenshots during the lab run, save to `blog/screenshots/` with numbered filenames
2. Force-commit screenshots to GitHub: `git add -f week-XX-*/blog/screenshots/ && git commit -m "week-XX: add blog screenshots" && git push`
3. Create `blog/BLOG_BLOGGER.html` — same CSS/structure as Week 02's `BLOG_BLOGGER.html`, light theme, `#jk-post` scoped styles, images using `raw.githubusercontent.com` URLs in this format:
   ```html
   <div class="separator" style="clear:both;"><a href="https://raw.githubusercontent.com/katta698/AWS-Platform-Engineering-Lab/main/week-XX-FOLDER/blog/screenshots/XX-filename.png" style="display:block;padding:1em 0;text-align:center;"><img alt="Alt text" border="0" width="600" src="https://raw.githubusercontent.com/katta698/AWS-Platform-Engineering-Lab/main/week-XX-FOLDER/blog/screenshots/XX-filename.png"/></a></div>
   ```
4. Commit BLOG_BLOGGER.html: `git add week-XX-*/blog/BLOG_BLOGGER.html && git commit -m "week-XX: add BLOG_BLOGGER.html" && git push`
5. Open BLOG_BLOGGER.html in browser to verify all images load from GitHub
6. Paste entire file into Blogger → New Post → HTML editor → publish
   - Labels must be added in Blogger's Labels field (sidebar), NOT inside the HTML file
7. Update SESSION_CONTEXT.md Completed Weeks section with blog URL

**DO NOT use dark theme** (`--bg: #0f1117` style) in BLOG_BLOGGER.html — Blogger uses light theme. Always base new BLOG_BLOGGER.html on `week-02-aurora-self-service/blog/BLOG_BLOGGER.html`.

**Week 03 specific:**
- `week-03-ssm-fleet-management/COMMANDS.md` — fleet visibility, patch compliance, simulate ServiceNow, Step Functions, SSM commands, maintenance window, S3 logs, Lambda logs, manual EC2 creation
- `week-03-ssm-fleet-management/SCREENSHOTS.md` — 19 screenshots including ServiceNow ticket submitted + closed
- Blog written and published via BLOG_BLOGGER.html — all 19 screenshots on GitHub raw CDN

---

## Standard Architecture Pattern (Used Every Week)

Every week follows this enterprise pattern:

```
ServiceNow Ticket (RITM)
      ↓
API Gateway (HTTPS + HMAC-signed webhook)
      ↓
Lambda: webhook_receiver (validates HMAC, starts Step Functions)
      ↓
Step Functions (orchestration)
      ↓
Lambda(s): provisioner / trigger
      ↓
AWS Resources provisioned
      ↓
Lambda: status_updater (closes ServiceNow ticket with details)
```

- 100% Terraform, modular design
- GitHub Actions CI/CD with OIDC (no static AWS credentials)
- Least-privilege IAM, secrets in SSM Parameter Store
- `force_destroy = true` on all S3 buckets
- All labs cost $0 when destroyed

---

## Completed Weeks

### Week 01 — Enterprise EC2 Self-Service ✅
- **Story:** ServiceNow ticket → running EC2 in 6 minutes
- **Services:** VPC, EC2, ASG, ALB, Lambda, Step Functions, API Gateway, CloudWatch
- **Resources:** 74 Terraform resources
- **Blog:** https://blog.jayanthkatta.com/2026/05/week-1-from-ticket-to-ec2-in-6-minutes.html
- **Folder:** `week-01-enterprise-ec2-provisioning/`

### Week 02 — Aurora Self-Service Database Platform ✅
- **Story:** ServiceNow ticket → isolated PostgreSQL DB with rotating credentials in 8.7 seconds
- **Services:** Aurora Serverless v2 (PostgreSQL 16), Secrets Manager, Lambda, Step Functions
- **Resources:** 67 Terraform resources
- **Blog:** https://blog.jayanthkatta.com/2026/05/week-2-automating-postgresql.html
- **Folder:** `week-02-aurora-self-service/`
- **Key lesson:** pg8000 layer built once via `build_layer.sh`, ARN stored in GitHub secret

### Week 03 — SSM Fleet Management + Patch Automation ✅ Complete
- **Story:** ServiceNow ticket → EC2 fleet onboarded to SSM + patch orchestration automated
- **Services:** SSM Fleet Manager, Patch Manager, Run Command, Inventory, Session Manager, Automation, State Manager
- **Folder:** `week-03-ssm-fleet-management/`
- **Project name:** `fleet-mgmt` (not `ssm-fleet` — AWS rejects SSM parameter paths starting with /ssm)
- **Validated:** 3 instances patched (2 ASG + 1 manual onboarded), 100% compliance, Step Functions all SUCCEEDED
- **Key lessons:**
  - AWS SSM Parameter Store rejects paths starting with `/ssm` (case-insensitive) — use `/fleet-mgmt/` prefix
  - VPC endpoints not supported in all AZs — use `aws_vpc_endpoint_service` data source to filter supported AZs
  - API Gateway `AWS_PROXY` uri must be `arn:aws:apigateway:{region}:lambda:path/2015-03-31/functions/{arn}/invocations`
  - SSM Automation reserved output names — `CommandId` is reserved, use `PatchCommandId`
  - AL2023 AMI snapshot requires minimum 30GB volume (not 20GB)
  - Step Functions CloudWatch logging needs full set of log delivery permissions
  - Onboard workflow applies PatchGroup tag + runs first scan — manual instances need this before Patch Manager sees them

### Week 04 — Glue Fleet Intelligence Platform ✅ Built (deploy + screenshots pending)
- **Story:** ServiceNow ticket → SSM data synced to S3 → Glue crawls + ETL transforms → Athena SQL over entire fleet
- **Services:** SSM Resource Data Sync, Glue Crawler, Glue Data Catalog, Glue ETL (PySpark), Athena, S3, Lambda, Step Functions, API Gateway
- **Folder:** `week-04-glue-fleet-intelligence/`
- **Project name:** `jay-fleet-intelligence`
- **Key insight:** Week 03 automates patching; Week 04 proves it worked via SQL
- **Key lessons:**
  - SSM Resource Data Sync requires S3 bucket policy with `ssm.amazonaws.com` trust (GetBucketAcl + PutObject) — without it sync silently delivers nothing
  - Upload Glue ETL script to S3 AFTER terraform apply creates the bucket
  - Deterministic ARN locals break Lambda ↔ Step Functions circular dependency
  - Parquet is ~10x cheaper than raw JSON for Athena scans ($5/TB)
  - S3 raw data lands under `ssm/AccountID=.../TypeName/.../data/` — Glue crawler path must include `ssm/` prefix
- **Blog:** `blog/week-04-blog.html` — awaiting screenshots before publish
- **Note:** Week 04 Glue Data Catalog becomes foundation for Week 31 (Lake Formation)

---

## All 53 Weeks — Quick Reference

### Phase 1 — Self-Service Platforms (Weeks 1–9)

| Week | Title | Key Services | Folder |
|------|-------|-------------|--------|
| 01 ✅ | Enterprise EC2 Self-Service | VPC, EC2, ASG, ALB, Lambda, Step Functions, API Gateway | `week-01-enterprise-ec2-provisioning` |
| 02 ✅ | Aurora Self-Service Database | Aurora Serverless v2, Secrets Manager, Lambda, Step Functions | `week-02-aurora-self-service` |
| 03 ✅ | SSM Fleet Management + Patching | SSM Fleet Manager, Patch Manager, Run Command, Automation | `week-03-ssm-fleet-management` |
| 04 📅 | Glue Fleet Intelligence | SSM Resource Data Sync, Glue, Athena, S3, Lambda, Step Functions | `week-04-glue-fleet-intelligence` |
| 05 📅 | S3 Intelligent Storage Platform | S3 Intelligent-Tiering, Lifecycle Policies, Cost Automation | `week-05-s3-intelligent-storage` |
| 06 📅 | Account Vending Machine | AWS Organizations, Control Tower, Account Factory, SCPs | `week-06-account-vending-machine` |
| 07 📅 | IAM Identity Center (SSO) | IAM Identity Center, Permission Sets, ServiceNow Access Requests | `week-07-iam-identity-center` |
| 08 📅 | Cost Anomaly Detection | Cost Explorer, Anomaly Detection, EventBridge, Lambda | `week-08-cost-anomaly-detection` |
| 09 📅 | ECS Fargate Self-Service | ECS Fargate, ECR, ALB, Task Definitions, ServiceNow | `week-09-ecs-fargate-self-service` |

### Phase 2 — Observability & Security (Weeks 10–17)

| Week | Title | Key Services | Folder |
|------|-------|-------------|--------|
| 10 📅 | Centralised Logging Platform | CloudWatch cross-account, OpenSearch, Log Aggregation | `week-10-centralised-logging` |
| 11 📅 | Security Hub + GuardDuty Automation | Security Hub, GuardDuty, EventBridge, Lambda auto-remediation | `week-11-security-hub-guardduty` |
| 12 📅 | AWS Config Compliance Automation | Config Rules, Auto-Remediation, Compliance Dashboard | `week-12-config-compliance` |
| 13 📅 | WAF + Shield Standard | WAF Web ACL, Rate Limiting, DDoS Protection, Managed Rules | `week-13-waf-shield` |
| 14 📅 | VPC Flow Logs + Network Intelligence | Flow Logs, Athena, traffic analysis, anomaly detection | `week-14-vpc-flow-logs` |
| 15 📅 | CloudTrail Lake + Audit Automation | CloudTrail Lake, SIEM integration, Query Editor | `week-15-cloudtrail-lake` |
| 16 📅 | Secrets Rotation at Scale | Cross-account rotation, rotation orchestration, break-glass access | `week-16-secrets-rotation` |
| 17 📅 | Private CA + Certificate Automation | ACM Private CA, internal PKI, auto-renewal pipeline | `week-17-private-ca` |

### Phase 3 — Containers & Modern Patterns (Weeks 18–25)

| Week | Title | Key Services | Folder |
|------|-------|-------------|--------|
| 18 📅 | EKS Cluster Self-Service | EKS, IRSA, namespace isolation, developer onboarding | `week-18-eks-self-service` |
| 19 📅 | GitOps with ArgoCD on EKS | ArgoCD, app-of-apps, progressive delivery, drift detection | `week-19-gitops-argocd` |
| 20 📅 | EventBridge Event-Driven Platform | EventBridge, event buses, schema registry, cross-account events | `week-20-eventbridge-platform` |
| 21 📅 | Blue/Green Deployment Automation | CodeDeploy, traffic shifting, automated rollback | `week-21-blue-green-deployment` |
| 22 📅 | Container Image Security Pipeline | ECR scanning, image signing, policy enforcement | `week-22-container-image-security` |
| 23 📅 | Service Mesh with App Mesh | Traffic management, observability, mTLS between services | `week-23-app-mesh` |
| 24 📅 | Chaos Engineering Platform | FIS fault injection, resilience testing, runbooks | `week-24-chaos-engineering` |
| 25 📅 | Serverless Microservices | API Gateway + Lambda, DynamoDB, SAM, local testing | `week-25-serverless-microservices` |

### Phase 4 — Data & Database (Weeks 26–33)

| Week | Title | Key Services | Folder |
|------|-------|-------------|--------|
| 26 📅 | DynamoDB Self-Service Platform | DynamoDB, DAX, on-demand capacity, table-per-tenant | `week-26-dynamodb-self-service` |
| 27 📅 | ElastiCache Redis Cluster | ElastiCache, Redis, caching layer, automated failover | `week-27-elasticache-redis` |
| 28 📅 | RDS Multi-Region with Read Replicas | RDS, read replicas, global database pattern, failover automation | `week-28-rds-multi-region` |
| 29 📅 | Database Migration Service | DMS, homogeneous + heterogeneous migrations, CDC, cutover | `week-29-dms-migration` |
| 30 📅 | Redshift Data Warehouse | Redshift Serverless, data sharing, Spectrum, RA3 | `week-30-redshift-warehouse` |
| 31 📅 | Lake Formation + Data Catalog | Lake Formation, Glue, fine-grained access, self-service data lake | `week-31-lake-formation` |
| 32 📅 | Kinesis Data Streaming Platform | Kinesis, Firehose, Lambda consumer, S3 sink | `week-32-kinesis-streaming` |
| 33 📅 | MSK Managed Kafka | MSK, consumer groups, Schema Registry, event streaming | `week-33-msk-kafka` |

### Phase 5 — Networking & Multi-Account (Weeks 34–41)

| Week | Title | Key Services | Folder |
|------|-------|-------------|--------|
| 34 📅 | Transit Gateway Hub-Spoke | Transit Gateway, route tables, shared services VPC | `week-34-transit-gateway` |
| 35 📅 | PrivateLink + Endpoint Services | PrivateLink, cross-account access, private SaaS exposure | `week-35-privatelink` |
| 36 📅 | Route 53 DNS Automation | Route 53, intelligent routing, health checks, private zones | `week-36-route53-automation` |
| 37 📅 | Network Firewall + Centralised Egress | Network Firewall, inspection VPC, stateful rules, domain filtering | `week-37-network-firewall` |
| 38 📅 | Global Accelerator | Global Accelerator, anycast, latency-based routing | `week-38-global-accelerator` |
| 39 📅 | Multi-Region Active-Active | Route 53 health checks, global resilience, data replication | `week-39-multi-region-active-active` |
| 40 📅 | Disaster Recovery Automation | Elastic DR, RTO/RPO automation, failover runbooks | `week-40-disaster-recovery` |
| 41 📅 | AWS Backup at Enterprise Scale | AWS Backup, cross-region, compliance reports | `week-41-aws-backup` |

### Phase 6 — AI, FinOps & Capstone (Weeks 42–53)

| Week | Title | Key Services | Folder |
|------|-------|-------------|--------|
| 42 📅 | Bedrock AI-Powered Self-Service | Bedrock, RAG, natural language infra requests, Lambda | `week-42-bedrock-ai-self-service` |
| 43 📅 | SageMaker ML Pipeline | SageMaker, model registry, endpoint automation, CI/CD | `week-43-sagemaker-ml-pipeline` |
| 44 📅 | FinOps Intelligence Dashboard | Cost Intelligence Dashboard, showback, chargeback, tagging | `week-44-finops-dashboard` |
| 45 📅 | Well-Architected Review Automation | WA Tool API, automated checks, remediation tracking | `week-45-well-architected` |
| 46 📅 | Service Control Policies at Scale | SCPs, guardrails, permission boundaries, deny-list patterns | `week-46-scp-at-scale` |
| 47 📅 | Lambda Power Tuning + Optimisation | Memory tuning, cold start reduction, provisioned concurrency | `week-47-lambda-optimisation` |
| 48 📅 | CodePipeline Enterprise CI/CD | Multi-stage pipeline, approval gates, cross-account deploy | `week-48-codepipeline-cicd` |
| 49 📅 | CloudFormation StackSets | Multi-account/multi-region baseline, drift detection | `week-49-stacksets` |
| 50 📅 | Internal Developer Portal | Backstage on ECS, service catalog, tech radar, TechDocs | `week-50-developer-portal` |
| 51 📅 | Step Functions Express Workflows | High-volume event processing, saga pattern, compensations | `week-51-sfn-express-workflows` |
| 52 📅 | Platform Reliability Engineering | SLOs, error budgets, automated incident response | `week-52-platform-reliability` |
| 53 📅 | Capstone: Full Cloud Platform | Everything integrated — self-service, GitOps, AI, FinOps, DR | `week-53-capstone` |

### Phase 5 — Networking & Multi-Account (Weeks 34–41)
34: Transit Gateway | 35: PrivateLink | 36: Route 53 Automation
37: Network Firewall | 38: Global Accelerator | 39: Multi-Region Active-Active | 40: DR Automation | 41: AWS Backup

### Phase 6 — AI, FinOps & Capstone (Weeks 42–53)
42: Bedrock AI Self-Service | 43: SageMaker ML Pipeline | 44: FinOps Dashboard
45: Well-Architected Automation | 46: SCPs at Scale | 47: Lambda Power Tuning
48: CodePipeline CI/CD | 49: CloudFormation StackSets | 50: Internal Developer Portal
51: Step Functions Express | 52: Platform Reliability Engineering | 53: Capstone

---

## GitHub Actions Workflows (at repo root .github/workflows/)

| Workflow | Purpose |
|----------|---------|
| `week-01-deploy.yml` | Deploy Week 1 EC2 infra |
| `week-01-destroy.yml` | Destroy Week 1 (type DESTROY) |
| `week-02-deploy.yml` | Deploy Week 2 Aurora infra |
| `week-02-destroy.yml` | Destroy Week 2 (type DESTROY + ticket ID) |
| `week-04-deploy.yml` | Deploy Week 4 Glue Fleet Intelligence infra |
| `week-04-destroy.yml` | Destroy Week 4 (type DESTROY) |

---

## How to Start a New Session

1. Open Claude (Cowork / desktop app)
2. Paste this entire file content
3. Say: "Connect my project folder: C:\Users\katta\Downloads\Engineering\AWS-Infrastructure-Projects\AWS-Platform-Engineering-Lab"
4. Tell Claude which week you're working on and what you need

---

## Cost Reference

| Week | Running cost | Destroyed |
|------|-------------|-----------|
| 01   | ~$65/month  | $0        |
| 02   | ~$75/month  | $0        |
| 04   | ~$2/run     | $0        |

Always run cleanup.sh when done for the day.
