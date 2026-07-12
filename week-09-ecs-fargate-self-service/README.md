# Week 09 — ECS Fargate Self-Service

**The story:** A team wants to deploy a containerized service. Today that means someone hand-builds an ECS cluster, task definition, ALB target group, listener rule, security groups, and auto-scaling — an hour of console/Terraform work, repeated (and often done inconsistently) every time. This week automates it: a ServiceNow ticket with an image URI and a port number becomes a running, load-balanced, auto-scaling Fargate service in minutes — no server management, no manual ALB wiring.

---

## What It Builds

**Static platform baseline (Terraform):**
- **VPC** — public subnets for the ALB, private subnets for Fargate tasks, no NAT Gateway
- **VPC Endpoints** — ECR (api + dkr), CloudWatch Logs (interface), S3 (gateway) — replace NAT Gateway for the private subnets' AWS API calls
- **ECS Cluster** — one shared Fargate cluster (`FARGATE` + `FARGATE_SPOT` capacity providers), Container Insights enabled
- **Shared Application Load Balancer** — one ALB serves every self-service ticket via path-based routing (`/<service-name>/*`); only a default 404 listener is static, per-service rules are added dynamically
- **IAM** — shared task execution role, and narrowly-scoped roles per Lambda
- **Lambda** — `webhook_receiver` (HMAC validation), `fargate_provisioner` (creates everything per-ticket), `status_notifier` (closes the ServiceNow ticket)
- **Step Functions** — orchestrates the two-Lambda provisioning pipeline
- **API Gateway** — HTTPS endpoint for the ServiceNow webhook

**Created dynamically per ticket (boto3 inside `fargate_provisioner`, not Terraform):**
ECR repository, task definition, ECS service, ALB target group, ALB listener rule, and an Application Auto Scaling target/policy — the same imperative-per-tenant pattern Week 2 used for `db_provisioner`.

---

## Architecture

```
ServiceNow Ticket (service_name, image_uri, container_port, cpu, memory, desired_count)
        |
        v
API Gateway (HTTPS + HMAC)
        |
        v
Lambda: webhook_receiver  --validates HMAC, starts Step Functions--
        |
        v
Step Functions: ProvisionService
        |
        v
Lambda: fargate_provisioner
  1. ecr:CreateRepository        (per-service image isolation)
  2. logs:CreateLogGroup         (/ecs/<project>-<service>)
  3. ecs:RegisterTaskDefinition  (awsvpc, FARGATE, execution role)
  4. elbv2:CreateTargetGroup     (target_type=ip)
  5. elbv2:CreateRule            (path-pattern /<service>/* on shared ALB)
  6. ecs:CreateService           (private subnets, ALB-only SG, no public IP)
  7. application-autoscaling:RegisterScalableTarget + PutScalingPolicy
        |
        v
Lambda: status_notifier  --closes ServiceNow ticket with the service URL--
        |
        v
Service reachable at http://<shared-alb-dns-name>/<service-name>/
```

---

## Key AWS Services

| Service | Role |
|---|---|
| ECS (Fargate launch type) | Runs containers with no host/server management |
| ECR | Private, scanned-on-push image storage, one repo per service |
| Application Load Balancer | Single shared entry point, path-based routing to every service |
| VPC Endpoints (ECR, Logs, S3) | Private-subnet AWS API access without a NAT Gateway |
| Lambda | Webhook validation, per-ticket provisioning, ServiceNow ticket close |
| Step Functions | Orchestrates the provisioning pipeline, gives a visual execution history per ticket |
| API Gateway | ServiceNow webhook endpoint |
| Application Auto Scaling | Target-tracking CPU scaling per service |
| IAM | Task execution role (shared) + task role separation, least-privilege Lambda roles |

---

## Design Decisions Worth Reading Before You Deploy

- **Path-based routing, not host-based.** The original plan used host-header routing (matching AWS's own ECS Express Mode pattern), but that needs an owned Route53 hosted zone to mint a subdomain per service. This lab doesn't have one wired up for this purpose, so every service is instead reachable at `http://<alb-dns-name>/<service-name>/` on the one shared ALB DNS name — same cost-consolidation benefit, no DNS dependency.
- **No NAT Gateway.** Fargate tasks run in private subnets with zero internet route; they reach ECR and CloudWatch Logs entirely through VPC interface endpoints (plus an S3 gateway endpoint, since ECR image layers live in S3). This mirrors Week 1's EC2 fleet, which used the same VPC-endpoints-instead-of-NAT pattern for the same reason: private subnets with no direct or NAT-routed internet path.
- **This pipeline provisions services, it does not build images.** A ticket supplies an existing `image_uri` (a public demo image for testing, or an image already pushed to the service's ECR repo by a separate CI pipeline). Building/pushing images is explicitly out of scope — that's Week 11's territory (CI/CD Pipeline).
- **Tickets close immediately after the ECS API calls succeed**, not after the task reaches `RUNNING`/healthy — matching Week 2's precedent (ticket closed 8.7 seconds after `CREATE DATABASE`, not after full readiness). The ticket close notes say health may take another 30-60 seconds.

---

## Prerequisites

- State is in **HCP Terraform** (not S3) — org: `Katta` | workspace: `week-09-dev`
- Terraform >= 1.10
- A ServiceNow instance + service account with REST API access to `sc_req_item`

---

## Deploy Steps

`week-09-dev` is a **VCS-connected HCP Terraform workspace** (same pattern as Weeks 5-8) — Terraform runs remotely from this GitHub repo, not from local CLI. ServiceNow creds, the webhook secret, and AWS auth (dynamic OIDC via `hcp-terraform-role`) are configured as HCP workspace variables, not a local `terraform.tfvars`.

```bash
bash scripts/deploy.sh   # rebuilds the 3 Lambda zips
git add lambda/*/*.zip
git commit -m "Update Lambda packages"
git push
```

Then in the HCP UI: **week-09-dev → Start new plan**, review, and confirm **Apply**.

Note: local `terraform apply`/`destroy` against this workspace will fail with `Saved plans not allowed for workspaces with a VCS connection` — that's expected; all applies/destroys go through the HCP UI.

### Triggering a test ticket

```bash
bash scripts/test_webhook.sh "$API_GATEWAY_URL" "$WEBHOOK_SECRET"
```

This deploys a public `nginx` image as `demo-nginx` — see `lambda/webhook_receiver/handler.py` for the full set of required ticket fields (`service_name`, `image_uri`, `container_port`, `cpu`, `memory`, `desired_count`).

---

## Cleanup

Destroy must be confirmed from the **HCP UI** (same VCS-connection restriction as deploy) — `bash scripts/cleanup.sh` walks through the pre-destroy checklist and waits for confirmation; it does not call `terraform destroy` itself.

Every self-service ticket's ECR repo, task definition, ECS service, target group, and listener rule were created imperatively via boto3 — they are **not** in Terraform state and will not be removed by a destroy run. Delete any test services first (see `scripts/cleanup.sh` for the exact AWS CLI commands), or the shared ALB/cluster/VPC destroy will fail on dependent target groups and ENIs still attached to a running service.

---

## Security

- HMAC-SHA256 signature validation on the ServiceNow webhook (same pattern as prior weeks)
- ECS tasks run in private subnets with no internet route — reachable only from the shared ALB's security group, never directly
- Two separate IAM roles per task: a shared execution role (pull image, write logs) and no default task role (self-service tasks get no AWS permissions unless a future ticket field adds one)
- `fargate_provisioner`'s IAM role is scoped to this project's resource-name prefix everywhere the underlying AWS API supports resource-level ARNs
- ECR scan-on-push + immutable tags on every per-service repository
- `terraform.tfvars` gitignored — never committed

---

## Cost

| Resource | Cost |
|---|---|
| Fargate compute (0.5 vCPU / 1GB, per task, 24/7) | ~$17.87/month per running task |
| Shared ALB | ~$24/month regardless of how many services sit behind it |
| VPC Interface Endpoints (ECR api + dkr + Logs) | ~$0.01/hour each (~$21.90/month combined, if left running) |
| ECR storage | $0.10/GB-month |
| Step Functions / Lambda / API Gateway | Well within free tier for lab-scale traffic |
| **Pipeline infra + test services destroyed** | **$0** |

Prices as of July 2026 — verify at [aws.amazon.com/fargate/pricing](https://aws.amazon.com/fargate/pricing/) and [aws.amazon.com/elasticloadbalancing/pricing](https://aws.amazon.com/elasticloadbalancing/pricing/).
