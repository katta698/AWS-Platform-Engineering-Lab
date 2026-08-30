# AWS Platform Engineering Lab

**53-week hands-on AWS lab series — building production-grade cloud infrastructure from scratch.**

> 14 years as a DBA → transitioning to Cloud Architecture.
> Every week: real code, real bugs, real fixes. No tutorials. No sandboxes.

---

## Roadmap — Year 1 planned, Year 2 themed

### Phase 1 — Self-Service Platforms (Weeks 1–9)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| [Week 01](./week-01-enterprise-ec2-provisioning) | Enterprise EC2 Self-Service | VPC, EC2, ASG, ALB, Lambda, Step Functions, API Gateway, ServiceNow | ✅ Complete |
| [Week 02](./week-02-aurora-self-service) | Aurora Self-Service Database Platform | Aurora Serverless, Secrets Manager, Lambda, Step Functions | ✅ Complete |
| [Week 03](./week-03-ssm-fleet-management) | SSM Fleet Management + Patch Automation | SSM Fleet Manager, Patch Manager, Run Command, Inventory, Session Manager, Automation | ✅ Complete |
| [Week 04](./week-04-glue-fleet-intelligence) | Glue Fleet Intelligence Platform | SSM Resource Data Sync, Glue Crawler, Glue ETL, Athena, S3, Lambda, Step Functions | ✅ Complete |
| [Week 05](./week-05-cost-anomaly-detection) | Cost Anomaly Detection | Cost Explorer ML, SNS ×2, Lambda, CloudWatch, HCP Terraform | ✅ Complete |
| [Week 06](./week-06-account-vending-machine) | Account Vending Machine (simulated, no Control Tower) | AWS Organizations, SCPs, Step Functions, Lambda, API Gateway, HCP Terraform | ✅ Complete |
| [Week 07](./week-07-identity-center-sso) | IAM Identity Center SSO (multi-account permission sets) | IAM Identity Center, Identity Store, Permission Sets, AWS Organizations, HCP Terraform | ✅ Complete |
| [Week 08](./week-08-s3-intelligent-storage) | S3 Intelligent Storage Platform | S3 Intelligent-Tiering, Lifecycle Policies, Cost Automation | ✅ Complete |
| [Week 09](./week-09-ecs-fargate-self-service) | ECS Fargate Self-Service | ECS Fargate, ECR, ALB, Task Definitions, ServiceNow | ✅ Complete |

### Phase 2 — Observability & Security (Weeks 10–17)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| [Week 10](./week-10-centralized-logging) | Centralised Logging Platform | CloudWatch OAM, Logs Centralization, Logs Insights, Lambda, EventBridge, SNS | ✅ Complete |
| [Week 11](./week-11-security-hub-guardduty) | Security Hub + GuardDuty Automation | Security Hub, GuardDuty, EventBridge, Lambda auto-remediation | ✅ Complete |
| [Week 12](./week-12-config-compliance-automation) | AWS Config Compliance Automation | Config Rules, Auto-Remediation, Compliance Dashboard | ✅ Complete |
| [Week 13](./week-13-waf-shield-protection) | WAF + Shield Standard | WAF Web ACL (both scopes), Rate Limiting, Anti-DDoS Managed Rules, CloudFront, API Gateway | ✅ Complete |
| [Week 14](./week-14-vpc-flow-logs-intelligence) | VPC Flow Logs + Network Intelligence | Flow Logs (record v11), S3 Parquet, Glue partition projection, Athena, Lambda, CloudWatch anomaly detection | ✅ Complete |
| [Week 15](./week-15-cloudtrail-audit-forensics) | CloudTrail Org Trail + Audit Forensics | CloudTrail organization trail, S3, Glue five-key partition projection, Athena, Lambda, static-threshold alarms (replaces CloudTrail Lake — closed to new customers 2026-05-31) | ✅ Complete |
| [Week 16](./week-16-devops-agent-investigations) | AWS DevOps Agent — Investigations, Graded | AWS DevOps Agent (agent space + associations) via the `awscc` provider, ServiceNow OAuth `client_credentials`, Lambda, EventBridge, SSM, S3, CloudWatch alarm, graded against Week 15's CloudTrail trail (planned as *Health Event Triage*; became an evaluation of whether the agent's conclusions can be trusted) | ✅ Complete |
| Week 17 | MCP Server for Platform Operations | Model Context Protocol server over the lab's own operational data (Athena, CloudWatch, Config) — makes Weeks 10–16 agent-consumable | 📅 Planned |

### Phase 3 — Containers & Modern Patterns (Weeks 18–25)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| Week 18 | EKS Cluster Self-Service | EKS, IRSA, namespace isolation, developer onboarding | 📅 Planned |
| Week 19 | GitOps with ArgoCD on EKS | ArgoCD, app-of-apps, progressive delivery, drift detection | 📅 Planned |
| Week 20 | EventBridge Event-Driven Platform | EventBridge, event buses, schema registry, cross-account events | 📅 Planned |
| Week 21 | Blue/Green Deployment Automation | CodeDeploy, traffic shifting, automated rollback | 📅 Planned |
| Week 22 | Container Image Security Pipeline | ECR scanning, image signing, policy enforcement | 📅 Planned |
| Week 23 | Service Networking with VPC Lattice | VPC Lattice service networks, cross-VPC/cross-account routing, auth policies (replaces App Mesh — shut down 2026-09-30) | 📅 Planned |
| Week 24 | Chaos Engineering + Agent Evaluation | FIS fault injection, resilience testing, runbooks — plus measuring whether AWS DevOps Agent finds a fault you deliberately caused | 📅 Planned |
| Week 25 | Serverless Microservices | API Gateway + Lambda, DynamoDB, SAM, local testing | 📅 Planned |

### Phase 4 — Data & Database (Weeks 26–33)

| Week | Project | Key AWS Services | Status |
|------|---------|-----------------|--------|
| Week 26 | DynamoDB Self-Service Platform | DynamoDB, DAX, on-demand capacity, table-per-tenant | 📅 Planned |
| Week 27 | ElastiCache for Valkey | ElastiCache Serverless for Valkey, caching layer, automated failover (Valkey is AWS's recommended engine for new deployments) | 📅 Planned |
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
| Week 42 | Agentic Self-Service with Bedrock AgentCore | Bedrock AgentCore runtime, tool use, natural language infra requests, guardrails | 📅 Planned |
| Week 43 | SageMaker ML Pipeline | SageMaker, model registry, endpoint automation, CI/CD | 📅 Planned |
| Week 44 | FinOps Intelligence Dashboard | Cost Intelligence Dashboard, showback, chargeback, tagging | 📅 Planned |
| Week 45 | Well-Architected Review Automation | WA Tool API, automated checks, remediation tracking | 📅 Planned |
| Week 46 | Service Control Policies at Scale | SCPs, guardrails, permission boundaries, deny-list patterns | 📅 Planned |
| Week 47 | Private CA + Certificate Automation | ACM Private CA, internal PKI, auto-renewal pipeline | 📅 Planned |
| Week 48 | CodePipeline Enterprise CI/CD | Multi-stage pipeline, approval gates, cross-account deploy | 📅 Planned |
| Week 49 | CloudFormation StackSets | Multi-account/multi-region baseline, drift detection | 📅 Planned |
| Week 50 | Internal Developer Portal | Backstage on ECS, service catalog, tech radar, TechDocs | 📅 Planned |
| Week 51 | Step Functions Express Workflows | High-volume event processing, saga pattern, compensations | 📅 Planned |
| Week 52 | Platform Reliability Engineering | SLOs, error budgets, agent-assisted incident response end to end | 📅 Planned |
| Week 53 | Capstone: Full Cloud Platform | Everything integrated — self-service, GitOps, AI, FinOps, DR | 📅 Planned |

## Year 2 — Weeks 54+ (themed backlog, not a fixed schedule)

Year 1 is planned week by week. **Year 2 deliberately is not.**

That is a lesson, not laziness. The Year 1 roadmap was written in early 2026 and by Week 15 two
of its topics had become unbuildable — CloudTrail Lake closed to new customers, App Mesh was
given a shutdown date — while the single biggest development in platform engineering that year
(agentic operations) had no slot at all, because the category did not exist when the list was
written. **A fixed two-year plan would rot twice as fast as a one-year plan.**

So Year 2 is a set of themes with candidate topics. **Actual topics are fixed 4–8 weeks out**,
against live AWS documentation and the real account, in each week's Pre-Build Briefing.

### Carried forward — displaced from Year 1, not dropped on merit

| Week | Project | Key AWS Services |
|------|---------|-----------------|
| Week 54 | Secrets Rotation at Scale | Secrets Manager, cross-account rotation, rotation orchestration, break-glass access |
| Week 55 | Lambda Power Tuning + Optimisation | Memory tuning, cold start reduction, provisioned concurrency, ARM migration |

### Candidate themes for Weeks 56+

| Theme | Candidate topics |
|---|---|
| **Agentic operations, deeper** | Agent evaluation harnesses, guardrails and approval boundaries, multi-agent workflows, Strands, agent cost control |
| **Compliance as evidence** | PCI/SOC2/HIPAA evidence automation, Audit Manager, control attestation from real telemetry |
| **Modern observability** | OpenTelemetry and ADOT, trace-based SLOs, Application Signals, cardinality and cost control |
| **Data platform** | S3 Tables and Iceberg, zero-ETL integrations, data contracts, cross-account data sharing |
| **Container platform, deeper** | Karpenter, EKS Auto Mode in anger, Fargate profiles, admission control, multi-tenancy |
| **Network modernisation** | Cloud WAN, IPv6 migration, Verified Access, egress inspection at scale |
| **Identity and access** | Verified Permissions, IAM Access Analyzer at scale, permission-boundary automation, workload identity |
| **Resilience engineering** | Application Recovery Controller, zonal shift, dependency mapping, game days |
| **Developer experience** | Spec-driven development with Kiro, golden paths, platform APIs, Terraform Stacks |
| **Migration and modernisation** | Application Migration Service, strangler-fig patterns, continuous modernisation tooling |
| **Edge and delivery** | CloudFront Functions, Lambda@Edge, multi-CDN, edge auth |
| **Cost engineering** | Unit economics, rightsizing automation, Savings Plans modelling, waste detection |

**How a Year 2 week gets chosen:** pick from the themes above based on what is genuinely current
and what the series has not yet proved, verify it is still buildable, then write the briefing.
A theme that stops mattering gets dropped without ceremony — that is the point of not fixing it
in advance.

> **Roadmap currency — reviewed 2026-08-18.** This roadmap is re-audited against live AWS
> documentation rather than followed blindly. Two originally-planned topics turned out to be
> unbuildable and were replaced: **CloudTrail Lake** (Week 15 — closed to new customers
> 2026-05-31) and **AWS App Mesh** (Week 23 — shuts down 2026-09-30, closed to new customers
> since 2024). Every week's Pre-Build Briefing re-verifies pricing, deprecations and provider
> arguments against current docs before any code is written.
>
> **Nothing is dropped to make room.** *Secrets Rotation at Scale* (was Week 16) and *Lambda
> Power Tuning + Optimisation* (was Week 47) lost Year 1 slots to more current material, not on
> merit, and open Year 2 at Weeks 54–55.

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
- Aurora Serverless (PostgreSQL 16) — scales 0 → 16 ACUs (scale-to-zero available April 2026)
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

## Week 07 — IAM Identity Center SSO (Multi-Account Permission Sets)

**The story:** A new engineer joins. Instead of an ops engineer manually creating IAM users in 3 accounts, they're added to a group in IAM Identity Center — and automatically get the right access to every account their group is assigned to. No per-account IAM users, no shared credentials, one place to audit.

**What it builds:**
- IAM Identity Center permission sets (`PlatformEngineer`, `ReadOnly`, `SecurityAuditor`) with managed + inline policies
- Identity Store groups (`Engineers`, `Auditors`) and users (`jane.engineer`) — all in Terraform
- Cross-account assignments: groups → permission sets → target accounts
- AWS auto-provisions `AWSReservedSSO_*` IAM roles in each target account
- Deployed via **HCP Terraform** (VCS-driven, org: Katta, workspace: week-07-dev)

**End-to-end validated:**
- Signed in as `jane.engineer` via the SSO portal — only saw the `PlatformEngineer` role for the assigned account (correct scoping)
- Federated session confirmed in CloudTrail — identity traced back to the Identity Center user, not an IAM user

**Resources:** Terraform-managed Identity Center resources + 3 auto-provisioned IAM roles per target account | **Blog:** https://jayanthkatta.com/blog/week-7-iam-identity-center-sso-multi-account-permission-sets/

---

## Week 08 — S3 Intelligent Storage Platform

**The story:** S3 buckets accumulate objects at Standard rates indefinitely. Nobody moves them. This platform automates tiering, enforces lifecycle rules, and emails a daily savings report showing exactly what the automation saved — with real dollar figures.

**What it builds:**
- S3 bucket with Intelligent-Tiering configuration — objects auto-move to Frequent/Infrequent/Archive Access tiers based on actual access patterns
- Lifecycle rules — multipart upload cleanup, version expiration, transition to Glacier
- SQS queue + Lambda (`storage-reporter`) — triggered daily by EventBridge, queries S3 Storage Lens metrics, publishes savings report to SNS
- SNS topic — formatted cost savings email to subscriber
- DLQ on SQS for failed Lambda invocations
- Deployed via **HCP Terraform** (VCS-driven, org: Katta, workspace: week-08-dev)

**Key lessons learned:**
- S3 Intelligent-Tiering + lifecycle rules on the same bucket requires careful rule ordering — IT handles access-pattern tiering, lifecycle handles age-based expiration; they coexist on non-overlapping prefixes
- Circular dependency (Lambda needs bucket ARN, bucket notification needs Lambda ARN) — resolved via deterministic locals using account ID
- S3 bucket notification `depends_on` Lambda permission or the notification silently fails

**Resources:** 18 Terraform resources | **Blog:** https://jayanthkatta.com/blog/week-8-s3-intelligent-storage-platform/

---

## Week 09 — ECS Fargate Self-Service

**The story:** Deploying a containerized service today means someone hand-builds an ECS cluster, task definition, ALB target group, listener rule, security groups, and auto-scaling policy — an hour of work, repeated inconsistently every time. This platform turns a ServiceNow ticket into a running, load-balanced, auto-scaling Fargate service in minutes, no server management, no manual ALB wiring.

**What it builds:**
- VPC with no NAT Gateway — private-subnet AWS API access via VPC Endpoints (ECR api + dkr, CloudWatch Logs, S3 gateway) instead
- Shared ECS cluster (`FARGATE` + `FARGATE_SPOT`) and shared Application Load Balancer — every self-service ticket adds a path-based routing rule (`/<service-name>/*`) to the same ALB rather than standing up a new one
- Lambda `webhook_receiver` (HMAC validation) → Step Functions `ProvisionService` → Lambda `fargate_provisioner` (creates ECR repo, task definition, target group, listener rule, ECS service, and auto-scaling target per ticket via boto3) → Lambda `status_notifier` (closes the ServiceNow ticket)
- Deployed via **HCP Terraform** (VCS-driven, org: Katta, workspace: week-09-dev)

**Key lessons learned:**
- No NAT Gateway rules out AWS's Public ECR Gallery (`public.ecr.aws`) — confirmed via a real `CannotPullContainerError` timeout; every ticket's image must already live in private ECR
- ALB has no path-rewrite action — the health check path must match the app's own `/<service>/` prefix exactly, or a genuinely healthy task gets killed
- Any Lambda behind a Step Functions `Retry` block must be idempotent — a retry re-invoked `fargate_provisioner` after a partial success and hit `InvalidParameterException: ... was not idempotent` until every creation call became check-before-create
- Application Auto Scaling needs its own one-time `iam:CreateServiceLinkedRole` per account — easy to miss until the first real ticket in a fresh account
- ServiceNow's Table API close call needs the ticket's `sys_id`, not its display number (`RITM...`) — a repeat of Week 4's own documented lesson, re-learned the hard way because it wasn't cross-checked before building this pipeline

**Resources:** 50 Terraform resources | **Blog:** https://jayanthkatta.com/blog/week-9-ecs-fargate-self-service/

---

## Week 10 — Centralised Logging Platform

**The story:** Every account in an organization hoards its own CloudWatch log groups — "show me every error across the platform in the last hour" means logging into N accounts and running the same query N times, and log evidence dies with the account that produced it. This platform fixes both with CloudWatch's 2025-era native primitives — no OpenSearch cluster, no Firehose pipeline, first centralized copy free.

**What it builds:**
- CloudWatch OAM sink + org-scoped sink policy in the monitoring account; OAM link in the source account — cross-account query-in-place for logs and metrics at $0, future vended accounts join automatically
- Organization-wide Logs Centralization rule (`aws_observabilityadmin_centralization_rule_for_organization`, provider ≥ 6.21) physically copying `/platform-lab/*` log groups into the management account
- Scheduled log-generator Lambda in the source account (structured JSON at weighted INFO/WARN/ERROR) so every layer has live multi-account traffic
- Metric filter → alarm → SNS email on the centralized stream, plus a cross-account dashboard
- Deployed via **HCP Terraform** (VCS-driven, org: Katta, workspace: week-10-dev); one manual org prerequisite (Organizations trusted access for CloudWatch — no Terraform resource exists)

**Key lessons learned:**
- The classic subscription-filter → Firehose → OpenSearch pattern is the architecture AWS itself is retiring (December 2026) — OAM + centralization rules replace it at near-zero cost
- OAM *shares* (query in place, free, dies with the source account); centralization *copies* (durable, new-data-only) — run both, each covers the other's gap
- An OAM link races the sink *policy*, not just the sink — `depends_on` the whole hub module or the first apply 403s
- The CLI trusted-access path silently skips the required service-linked role the console would auto-create — pair `enable-aws-service-access` with an explicit `create-service-linked-role`
- The org's one-time centralization onboarding can take a very long time ("Centralization is currently initializing") — never put an org-wide enablement with unbounded activation time on your critical path, and never add a `depends_on` that isn't structurally required
- Infrequent Access log class halves ingestion cost but permanently disables metric filters — an irreversible per-log-group choice that must be made with the alerting design in view

**Resources:** 17 Terraform resources | **Blog:** https://jayanthkatta.com/blog/week-10-centralized-logging/

---

## Week 11 — Security Hub + GuardDuty Auto-Remediation

**The story:** A security finding is worthless if it sits in a console nobody watches. GuardDuty and Security Hub are very good at *finding* misconfigurations — an open management port, a public S3 bucket — but mean-time-to-remediate for the boring, mechanical ones is measured in hours or days, exactly the window an attacker needs. This platform closes the loop: clear-cut findings get fixed automatically in seconds, while active-threat findings that need human judgement are escalated instead of touched.

**What it builds:**
- Security Hub CSPM (classic, not the Dec-2025 unified v2 — the Terraform provider doesn't stably support v2 yet) with the AWS Foundational Security Best Practices standard subscribed, plus a finding aggregator and an automation rule that escalates production-tagged failures to CRITICAL before anything routes
- GuardDuty foundational detector (Extended Threat Detection auto-enabled, no extra cost)
- EventBridge rules matching `Workflow.Status = NEW` routing findings by control ID to three Lambdas: two tag-gated auto-remediators (revoke world-open security-group ingress, apply S3 Block Public Access) and one notify-only threat handler for GuardDuty findings
- Every automated action writes back to the finding via `BatchUpdateFindings`; a shared SNS topic delivers results and alerts; a 14-day SQS DLQ + CloudWatch alarm catch any failed remediation
- Deployed via **HCP Terraform** (VCS-driven, org: Katta, workspace: week-11-dev)

**Key lessons learned:**
- The `aws_securityhub_standards_subscription` resource's 3-minute default create timeout is too short for FSBP's ~300 controls on first enablement — needs `timeouts { create = "15m" }`
- An HCP run created via the API pins to the *already-ingressed* configuration version, not necessarily your latest commit — queuing a run and deploying your latest code are not automatically the same thing
- **The critical one:** an EventBridge rule matching both `Workflow.Status = NEW` and `NOTIFIED` created an infinite feedback loop — the Lambda's own `BatchUpdateFindings` write-back re-emitted an event that re-matched the rule and re-invoked itself, firing ~8×/minute against a real bucket until caught. A handler that writes back to the same finding store it's triggered by must keep its writeback status outside its own trigger pattern
- Security Hub's FSBP controls are backed by AWS Config — no configuration recorder, no findings, silently

**Resources:** 30 Terraform resources | **Blog:** https://jayanthkatta.com/blog/week-11-security-hub-guardduty/

---

## Week 12 — AWS Config Compliance Automation

**The story:** Compliance drift is rarely dramatic. Somebody turns off versioning on a bucket to stop a lifecycle rule complaining, someone else launches an instance without the tag the cost report groups by, and neither shows up until an audit or an invoice. Detecting that is only half the job — a rule that reports a bucket as non-compliant every day for six months has not improved anything. This week detects the drift *and* fixes the mechanical cases automatically, then reports what is left.

**What it builds:**
- **One AWS Config conformance pack** (`week12-cfgcompliance-pack`) rendered from a CFN-style YAML template via `templatefile()`, containing three managed rules: `required-tags`, `s3-bucket-versioning-enabled`, and `s3-bucket-server-side-encryption-enabled` — all three confirmed absent from the ~300 `securityhub-*` rules Week 11's FSBP standard already created
- **Auto-remediation using AWS-managed SSM Automation documents** — `AWS-ConfigureS3BucketVersioning` and `AWS-EnableS3BucketEncryption`, both verified to exist and Amazon-owned before use, rather than the plausible-sounding `AWSConfigRemediation-*` names that do not
- **Its own Config configuration recorder**, because the account's shared one was deleted mid-build by an unrelated project's cleanup and took every rule with it
- A `compliance_reporter` Lambda that **discovers the real rule names at runtime** via `DescribeConformancePackCompliance`, publishing a summary to SNS
- Deployed via **HCP Terraform** (VCS-driven, org: Katta, workspace: week-12-dev)

**Key lessons learned:**
- **A conformance pack defines its own rules; it does not wrap externally-created ones.** The original design had standalone `aws_config_config_rule` resources *plus* a pack around them, which would have duplicated every rule. Pick one — do not create the same rule both ways
- **AWS Config appends a generated suffix to every rule name inside a conformance pack** (`week12-required-tags-conformance-pack-<id>`, not `week12-required-tags`). A hardcoded rule-name env var silently matches nothing, so the reporter has to discover names rather than assume them
- **Config `Scope` cannot combine `ComplianceResourceTypes` with `TagKey`/`TagValue`** — it is resource-type-based or tag-based, never both. Only a real apply catches this; a web search during the briefing had suggested otherwise and was wrong
- **S3 bucket-level admin actions do not support `aws:ResourceTag` IAM conditions at all.** `PutBucketVersioning` and `PutBucketEncryption` with a tag condition do not error — the statement simply never matches, so it grants nothing. This does *not* generalise from Week 11, where the same trick works fine on EC2 security groups. Verify per action, not per service
- **`boto3.client("configservice")` does not exist** — the client name is `"config"`; `configservice` is only the AWS CLI's command namespace. Caught by a real invoke, not by `terraform validate` or `py_compile`

**Resources:** 23 Terraform resources | **Blog:** https://jayanthkatta.com/blog/week-12-config-compliance-automation/

---

## Week 13 — AWS WAF + Shield Standard

**The story:** AWS Shield Standard is free, always on, and has no Terraform resource — it stops layer 3/4 volumetric attacks and cannot read a single line of HTTP. The layer where credential stuffing, path scanners and Log4Shell probes actually live is layer 7, and that is AWS WAF's job. The common failure is assuming DDoS protection means Shield Advanced at $3,000/month, concluding it is unaffordable, and shipping nothing at all.

**What it builds:**
- **Two web ACLs, one per WAF scope** — `CLOUDFRONT` at the edge and `REGIONAL` on the API Gateway stage. Two rather than one because the API Gateway invoke URL stays publicly reachable, so an edge-only firewall is trivially bypassed
- Five rules per ACL: break-glass IP set, rate-based rule on a 60-second evaluation window, `AWSManagedRulesCommonRuleSet`, `AWSManagedRulesKnownBadInputsRuleSet`, and `AWSManagedRulesAntiDDoSRuleSet` — **953 of the 1,500 included WCUs**, so no capacity overage
- CloudFront → API Gateway REST API → Lambda echo origin as the protected application (REST, not HTTP API — WAF cannot attach to HTTP APIs at all)
- WAF logging to CloudWatch with `authorization`/`cookie`/`x-api-key` redacted, plus a per-web-ACL log resource policy rather than contributing to the shared account-wide `AWSWAF-LOGS` policy
- `BlockedRequests` **and** `CountedRequests` alarms → SNS, because during the Count phase `BlockedRequests` stays at zero and would report "all clear" while rules match heavily
- Deployed via **HCP Terraform** (VCS-driven, org: Katta, workspace: week-13-dev), Count mode first and flipped to Block only after the evidence justified it

**Key lessons learned:**
- The Anti-DDoS managed rule group **requires** a non-empty `exempt_uri_regular_expression` list when its challenge action is enabled. The Terraform provider documents the field as optional; AWS rejects `CreateWebACL` outright. Neither `validate` nor `plan` catches it
- **CLOUDFRONT-scope WAF metrics carry no `Region` dimension at all.** Setting it to `"Global"` is a plausible-looking guess that matches no metric series, so the alarm sits in `INSUFFICIENT_DATA` forever while appearing healthy. Regional metrics *do* carry it. Related: the `Rule` dimension uses `visibility_config.metric_name`, not the rule's `name`
- **An HTTP status is not a WAF verdict**, especially in Count mode where everything returns 200 by design. API Gateway's 400/405 and CloudFront's 403 have nothing to do with WAF. Only `CountedRequests`/`BlockedRequests` or the WAF logs are evidence
- Shield Advanced's automatic application-layer mitigation **sunsets 2027-01-01**, replaced by the Anti-DDoS managed rule group at the standard $1/month — no Shield Advanced subscription required

**Resources:** 33 Terraform resources | **Blog:** https://jayanthkatta.com/blog/week-13-waf-shield-protection/

---

## Week 14 — VPC Flow Logs + Network Intelligence

**The story:** flow logs get switched on for a compliance checkbox, write tens of gigabytes a month into a bucket nobody has permission to read, and are never queried again — until an incident, when the answer is technically sitting in S3 and unreachable in under a day. Flow logs are pure cost until someone builds the query layer, and the query layer is the part that always gets deferred. You pay $0.25/GB ingested whether or not a single query ever runs.

**What it builds:**
- **Flow logs to S3 in Parquet**, hive-partitioned and hourly, using a **record version 11** custom format of 32 fields — S3 rather than CloudWatch Logs is a 2× cost decision ($0.25/GB vs $0.50/GB) and Parquet is only offered on the S3 path
- A small VPC built to produce identifiable traffic: a private generator egressing through both a **NAT gateway** (billed) and a **free S3 gateway endpoint**, plus an internet-reachable instance whose security group has **no ingress rules at all** — those denials are what create the REJECT records the detection queries analyse
- **Glue table with partition projection, no crawler** — flow log prefixes are fully deterministic, so a crawler would pay DPU-time to rediscover a known structure and lag behind new partitions
- **Athena workgroup with a 10 GB per-query scan ceiling**, enforced at workgroup level so no client can opt out. Athena bills $5/TB scanned with no default limit
- Seven saved Athena queries (top talkers, rejected traffic, port-scan candidates, NAT cost attribution, traffic-path contrast, next-hop trace, and a partition sanity check)
- An hourly `flow_analyzer` Lambda publishing custom metrics, with a **deliberately mixed** alarm strategy: anomaly-detection bands where normal is unknown (traffic volume, NAT egress) and static thresholds where zero is the correct value (port scans, DLQ depth, analyzer silence)
- Deployed via **HCP Terraform** (VCS-driven, org: Katta, workspace: week-14-dev)

**Key lessons learned:**
- **`traffic_path` cannot attribute NAT cost — it is relative to the capture point, not the journey.** Measured at the sending instance's own ENI, NAT-bound traffic records `traffic_path = 1` ("same VPC"), because that is literally what the next hop is. The NAT's own ENI records `8` for the same bytes but carries no instance tag. The documented value `2` never appeared in real data at all. The **record v11 `next_hop_interface_type`** field is what actually solves it, putting the team's tag and the NAT destination on one row
- **`data.aws_availability_zones` with `state = "available"` also returns opted-in Local Zones.** One wrong AZ produced three unrelated-looking failures at once — NAT gateway, gp3 and Graviton all unavailable. Filter on `zone-type` and intersect with the instance type's real offering list
- **An S3-destination flow log rejects `iam_role_arn` outright.** A delivery role applies only to the CloudWatch Logs destination; for S3, permissions come from the bucket policy. The v11 tag fields are served by the auto-created `AWSServiceRoleForVPCFlowLogs` service-linked role, so the only grant that matters is `iam:CreateServiceLinkedRole` on whatever runs Terraform
- **Flow log tag values arrive percent-encoded** — `platform-engineering` is delivered as `platform%2Dengineering`. Every tag column needs `url_decode()` or grouping silently splits
- **Every failure mode in this build is silent.** A projection template that does not match the delivered prefixes returns zero rows and reports `SUCCEEDED`; missing tag permissions produce a column of `-`. Hence a `verify_pipeline.sh` that checks a real delivered S3 key against the template rather than re-reading the config

**Resources:** 58 Terraform resources | **Blog:** https://jayanthkatta.com/blog/week-14-vpc-flow-logs-intelligence/

---

## Week 15 — CloudTrail Organization Trail + Audit Forensics

**The story:** Weeks 11 and 12 answer *"is something wrong?"* — Security Hub and GuardDuty find the open security group and close it; Config reports whether a resource is compliant. Both describe **state**. Neither can say **who did it, when, from where, and what else they touched** — and once an auto-remediation has tidied the problem away, the action record is the only evidence it ever happened. The motivating incident is real and from this lab: during Week 12 the account's Config recorder was deleted mid-build by an unrelated project's cleanup script, and *who deleted it* was never answerable by anyone.

**What it builds:**
- A **CloudTrail organization trail** — management events only, multi-region, log file validation on — covering every account in the org including accounts created after the trail exists
- **Five-key partition projection** over `AWSLogs/<org-id>/<account>/CloudTrail/<region>/YYYY/MM/DD/`, where AWS documents one key for a single account, or manual `ALTER TABLE ADD PARTITION` for an org — then recommends CloudTrail Lake, which closed to new customers on 2026-05-31
- **Athena workgroup with a 10 GB per-query scan ceiling**, so a forensic query written under incident pressure cannot become an unbounded bill
- Seven saved queries (partition sanity check, who-changed-this-resource, principal timeline, changes-outside-Terraform, root usage, console login without MFA, activity in unexpected regions)
- A daily `audit_analyzer` Lambda turning three should-be-zero questions into CloudWatch metrics, with **six alarms that are all static thresholds** — the deliberate opposite of Week 14, because a metric whose correct value is a fact wants a fixed threshold, not a learned baseline. Also 30× cheaper, and it leaves no orphaned anomaly detectors on teardown
- Deployed via **HCP Terraform** (VCS-driven, org: Katta, workspace: week-15-dev)

**Key lessons learned:**
- **A federated sign-in is not an MFA-less sign-in, and getting this wrong makes the alarm useless.** IAM Identity Center, SAML and any external IdP satisfy MFA *at the identity provider*, then federate into the console — so CloudTrail records `MFAUsed = "No"` on a fully MFA-protected login. The first version of the query counted those rows and went into ALARM on six logins generated by this repo's own screenshot tooling. In any estate using Identity Center that means alarming on **every normal login**, which is worse than no alarm: it trains you to ignore the channel. Scope to `useridentity.type IN ('IAMUser','Root')` and read `MFAUsed` from `additionalEventData` — a root or IAM-user login has no assumed-role session context, so `sessioncontext.attributes.mfaauthenticated` is NULL even when MFA was used
- **"The first copy of management events is free" is only true if nothing already claimed it.** A pre-existing trail from an unrelated project held the free copy for us-east-1, making this one a second copy at $2.00/100k. Run `aws cloudtrail describe-trails` before quoting $0 — the README was written with the wrong number first
- **Projection enums are a standing liability.** Dates project infinitely; accounts and regions cannot, so both are enums. An account missing from the enum has its events sitting in S3, intact, and invisible to every query, with no error anywhere. Deriving the list from live org state fixes the *code* but not the deployed *table* — that still needs an apply
- **The region enum must cover every enabled region, not just the ones in use.** One of the questions is "did anything happen in a region we don't use?", and a narrow enum makes that structurally unanswerable — returning a confident empty result forever
- **Redaction that only knows your own account ID is not enough once an org is involved.** An org trail puts one S3 folder per member account under the org prefix and an `account` column in every result; a sibling account ID rendered in plain text while the caller's was correctly masked. Six other accounts were in scope
- **The audit trail caught a bug in the tooling that built it.** `MSYS_NO_PATHCONV` (already documented from Week 12, and not applied) mangled SSM parameter names into `C:/Program Files/Git/...`. The script's soft `WARN` lines made it look uniformly broken; CloudTrail showed two of three calls had actually *succeeded* against a garbage resource name — a partially successful run, which is worse than a clean failure

**Resources:** 36 Terraform resources | **Blog:** https://jayanthkatta.com/blog/week-15-cloudtrail-audit-forensics/

---

## Week 16 — AWS DevOps Agent: Investigations, Graded

**The story:** an investigating agent does not return a metric, it returns a **narrative** — *"the IAM change at 15:57 removed the parameter read, here is the evidence."* A wrong metric looks wrong; a wrong explanation reads like an explanation. So this week is not a demonstration that an agent can investigate — AWS's marketing covers that. It is an **evaluation**: break something in a known way, write the true cause down *before* asking, and grade the agent's conclusion against Week 15's CloudTrail attribution, which is fact rather than opinion.

**What it builds:**
- An **agent space** and two **associations** (the monitored AWS account, and ServiceNow) — the agent space is the blast radius, and everything it can reach is a Terraform resource rather than a console click
- A deliberately small **observed workload** — a scheduled Lambda that reads an SSM parameter and writes to S3, with its permissions split across two inline policies so the break can detach exactly one
- `break_it.sh` / `fix_it.sh` — the break confirms the workload is healthy first, writes a **ground-truth ledger** with the cause, the expected symptom, what did *not* change, and the marking scheme, and only then runs a single `delete-role-policy`
- `measure_usage.sh` — reads the usage meter, because this service has **no spend ceiling** and observation is the only control available
- Deployed via **HCP Terraform** (VCS-driven, workspace: week-16-dev), using the **`awscc`** provider throughout

**Key lessons learned:**
- **The `hashicorp/aws` provider has no DevOps Agent resources** ([#46894](https://github.com/hashicorp/terraform-provider-aws/issues/46894) still open). `awscc` generates from the CloudFormation registry, so a service appears there as soon as its CFN types go LIVE — the price is machine-generated shapes and thin documentation
- **`service_id = "aws"` is a reserved literal that appears in no schema.** Every association needs one, the `ServiceType` enum contains only third-party integrations, and `list-services` returns empty on a fresh account. The value was found in AWS's own published Terraform sample and nowhere else
- **Through IaC this agent can only ever read.** `AccountType` accepts exactly one value (`monitor`), and *neither* CloudFormation resource exposes an actions-role property — so an estate built entirely in code gets a read-only agent whether or not anyone decided that. The console shows the capability exists; enabling it means stepping outside Terraform
- **ServiceNow `client_credentials` needs three separate settings to agree, and reports all three failures identically.** A system property enables the grant at all; **Client Type** must be *Integration as a Service*; an **OAuth Application User** must be assigned. The errors — "check your service credentials", `401 access_denied`, `unauthorized_client` — all read like a wrong secret. None of them are
- **The registration is not the integration.** OAuth issued tokens and the association was created, and **zero ServiceNow incidents were ever produced**. "Configured" and "working" are separate claims; check the destination system, not the source config
- **An investigation costs a flat rate regardless of effort** — 0.168 hrs / $5.03 for both runs, though the second visibly did more work. The meter also **reads 0.0 until the work completes**, which materially weakens watching it as a live guardrail
- **I left the answer key in the environment.** The SSM parameter's Terraform `description` said *"Revoking the role's ssm:GetParameter is the deliberate break"* — and the agent quoted it back in its root cause. Resource descriptions, names and tags are **inputs to the agent**, not annotations for humans
- **Read the mitigation plan; do not run it.** The first run proposed adding the permission to the `baseline` policy rather than restoring the deleted `config-read` resource — restoring service while deepening Terraform drift. The second run proposed the correct repair *plus* an SCP preventing recurrence. Same agent, same account, two runs, two qualities of remediation
- **The grading method was only ever tested against right answers.** Both runs were correct, so nothing establishes that the marking scheme would catch a confident wrong one. N=2, one failure mode — the shape of an answer, not the answer

**Resources:** 24 Terraform resources | **Cost:** $23.28 | **Blog:** https://jayanthkatta.com/blog/week-16-devops-agent-investigations/

---

## Standalone Posts

Technical deep-dives and guides published outside the weekly series.

| Post | Topic | Blog |
|------|-------|------|
| EBS Savings Dashboard — Phase 1 | EBS volume cost analysis, rightsizing, unattached volume detection | https://jayanthkatta.com/blog/ebs-savings-dashboard-phase1/ |

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

> **Why the table stops at Week 04:** from Week 05 onward, every week deploys through a **VCS-connected HCP Terraform workspace** (`week-XX-dev`, org `Katta`) instead of GitHub Actions — VCS-connected workspaces don't accept `terraform apply`/`destroy` from CI, so per-week workflow files would be dead code (Week 5 shipped them, discovered exactly that, and deleted them). For those weeks: push to `main` triggers a remote plan in HCP, applies are confirmed in the HCP UI, and destroys run from the workspace's Destruction settings. HCP authenticates to AWS via its own OIDC role (`hcp-terraform-role`) — still no static credentials anywhere.

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

All labs are designed to cost **$0 between sessions**.

For Weeks 01–04 (local Terraform / GitHub Actions):

```bash
# Done for the day
sh scripts/cleanup.sh   # destroys everything in ~5 min

# Back next session
sh scripts/deploy.sh    # rebuilds everything in ~10 min
```

For Weeks 05+ (VCS-driven HCP Terraform workspaces), destroy and rebuild run in
HCP instead: **workspace → Settings → Destruction and Deletion → Queue destroy
plan**, and a git push (or "Start new plan") to rebuild.

| Week | Cost if left running | Cost destroyed |
|------|---------------------|----------------|
| 01   | ~$65/month          | $0             |
| 02   | ~$75/month          | $0             |
| 03   | ~$48/month          | $0             |
| 04   | ~$0.22/run          | $0             |
| 05   | ~$0/month (free tier) | $0           |
| 06   | ~$0/month (Organizations/SCPs free; pennies per pipeline run) | $0 — but vended accounts are real and persist (separate manual cleanup) |
| 07   | $0/month (IAM Identity Center is free) | $0 |
| 08   | ~$1/month at lab data volumes | $0 |
| 09   | ~$65/month (shared ALB ~$24 + VPC endpoints ~$22 + ~$18/running task) | $0 |
| 10   | < $2/month (OAM free; first centralized copy free; bounded log storage) | $0 |
| 11   | ~$5-20/month (GuardDuty + Security Hub CSPM checks; 30-day free trial covers the lab window) | $0 |
| 12   | ~$1-5/month (Config recorder now bills account-wide; rule/conformance-pack evaluations are pennies) | $0 — but also removes the account's only Config recorder, check Week 11 dependency first |
| 13   | ~$20/month (2 web ACLs @ $5 + 10 rules @ $1; **prorated hourly**). Billed **$4.93** for the four days it actually existed, 5-8 Aug &mdash; about $1.20/day. The original note said "a build-test-destroy day is under $1", which was right per day and wrong about the week, because the build ran four days rather than one | $0 |
| 14   | ~$33/month (**~75% is the NAT gateway** at $0.045/hr + $0.045/GB, which bills with no usage signal to remind you; 2 anomaly alarms @ $3 each, prorated hourly) | $0 |
| 15   | ~$9-12/month — **not the $0 the free-tier line implies.** One free copy of management events per region exists, but an unrelated project's trail already held it, so this is a *second* copy at $2.00/100k events (~450-600k/month measured). A build-and-destroy is $1-2. No NAT, no always-on compute, 6 static alarms @ $0.10 | $0 |
| 16   | ~$0.12/month idle (one static alarm @ $0.10; the agent space itself is **$0 while idle**, verified on every meter). The real exposure is per-use and **uncapped** — $0.0083/agent-second (~$0.50/min) with no budget, duration or task limit anywhere in the schema, unlike Weeks 14–15 where Athena was capped at workgroup level. Actual spend was **$23.28**: two investigations at a flat $5.03 each, plus a one-time **$13.22 `system learning`** charge that is not one of the three billed categories AWS publishes | $0 |

---

## About

Jay Katta — 14 years as a DBA, transitioning to Cloud Architecture.
Building one production-grade AWS pattern every week for 52 weeks.

- GitHub: [@katta698](https://github.com/katta698)
- Blog: https://jayanthkatta.com/blog/
