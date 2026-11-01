# Week 05 — Cost Anomaly Detection

**What you build:** Ask a different question — "is this unlike me" — using Cost Anomaly Detection, which models expected spend per service per day, and turn what it emits into an email a person can act on.

Automated AWS cost anomaly detection using Cost Explorer ML, SNS, and Lambda.
Deployed and managed via **HCP Terraform** (VCS-driven, org: Katta).

| | |
|---|---|
| **Cost** | ~$0 &mdash; every component is free at this scale |
| **Provisioning** | 100% IaC (Terraform) |

> **Status:** built and validated.

## 1. Prerequisites

| Requirement | Why | How to check |
|---|---|---|
| Cost Explorer enabled on the account | Anomaly detection is part of it, and nothing can be created until it is switched on — a one-time action in the console | The Cost Management console shows cost data rather than an enable prompt |
| Billing data history | The detector learns a normal pattern before it can call anything abnormal, so a brand-new account has nothing to compare against | Expect no anomalies at all on the first days |
| An email address to subscribe | An SNS subscription stays pending until the confirmation link is clicked, and an unconfirmed topic delivers nothing while reporting success | `aws sns list-subscriptions-by-topic` shows an ARN, not `PendingConfirmation` |
| An HCP Terraform workspace with OIDC | Keeps credentials out of the repo; the workspace is VCS-connected, so destroy is driven from the HCP UI | The run page shows an applied run against the committed configuration |

## 2. Source files

### Infrastructure
| Resource | Name |
|---|---|
| Cost Anomaly Monitor | `week05-dev-monitor` |
| Cost Anomaly Subscription | `week05-dev-subscription` |
| SNS Topic (raw) | `week05-dev-raw-anomaly` |
| SNS Topic (alert) | `week05-dev-cost-alert` |
| Lambda | `week05-dev-cost-alerter` |
| IAM Role | `week05-dev-cost-alerter-role` |
| CloudWatch Log Group | `/aws/lambda/week05-dev-cost-alerter` |

## 3. Deploy

### Quick Start
See [docs/execution-guide.md](docs/execution-guide.md) for full HCP setup, validation steps, and troubleshooting.

```bash
# After HCP workspace is configured
cd terraform/environments/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars: set alert_email
terraform login
terraform init
terraform plan
terraform apply
```
### HCP Terraform
State is in HCP (not S3). Org: `Katta` | Workspace: `week-05-dev` | Mode: VCS-driven.
Plan on PR → Apply on merge to main.

## 4. Run it

This lab has no separate run step. The workload is what the deploy creates, and what to look at afterwards is in [5. Validation](#5-validation).

## 5. Validation

| Test | Expected |
|---|---|
| The stack deploys | A clean apply from a VCS-connected workspace |
| The monitor exists and covers everything | A DIMENSIONAL monitor across all services |
| The subscription has the intended threshold | Immediate delivery above $10 of absolute impact |
| Both topics exist and are separate | One topic AWS publishes to, one a person subscribes to |
| The formatter runs | A test invocation publishes to the formatted topic |
| A human gets something readable | Expected against actual spend, with a root cause |
| A real anomaly is detected end to end | AWS raises one by itself and the mail arrives |
| Teardown | Everything removed |

The results recorded when this lab was built are in the article.

## 6. Cleanup

```bash
./scripts/cleanup.sh
```

cleanup.sh — destroys all week-05 resources

## Cost

All resources are within AWS Free Tier or near-zero cost:
- Cost Anomaly Detection: free
- SNS: first 1M publishes/month free
- Lambda: well within free tier
- Destroyed: $0

## Troubleshooting

**The monitor and the subscription were both created and no alert ever fired. No error in CloudWatch, nothing in the console**.
The SNS topic policy named `budgets.amazonaws.com` as the principal. Cost Anomaly Detection publishes as `costalerts.amazonaws.com`, and AWS drops a refused publish silently.
*Fix:* Name the right principal.

**Days passed with no real alert, even while running charges up deliberately**.
Not a fault. The detector needs enough spend history to build a baseline before it can call anything anomalous, and a new monitor has none.
*Fix:* Prove the delivery path with a test event, and wait for the baseline for the detection itself.

**The function ran successfully and no email arrived**.
The subscription was still in `PendingConfirmation`. SNS does not deliver to an unconfirmed endpoint, and does not treat that as an error.
*Fix:* Click the confirmation link.

**Every plan failed with `No Terraform configuration files found in working directory`, for a directory that was plainly in the repo**.
Partly established. The HCP GitHub App's repository access was scoped to a different repository, which explains the clone having nothing in it. Granting access did not on its own fix it.
*Fix:* Enabling "Include submodules on clone" is what broke the cycle. The repository has no submodules, so why that mattered is unconfirmed, and it is recorded here as what worked rather than as an explanation.

## References

- [The article for this week](https://jayanthkatta.com/blog/week-5-cost-anomaly-detection-with-aws-cost-explorer-sns-and/) &mdash; the problem, the findings and the measured cost.
- [This week's source](https://github.com/katta698/AWS-Platform-Engineering-Lab/tree/main/week-05-cost-anomaly-detection)

## The Story

Your AWS bill spikes unexpectedly. A fixed budget alert would have missed it — the threshold wasn't crossed, but spending is 125% above what the ML model predicted. This week automates that detection: Cost Anomaly Detection fires immediately when any service exceeds its ML baseline by $10+, Lambda formats the raw payload into a readable email, and the alert lands in your inbox within minutes.

## Architecture

```
AWS Cost Explorer (ML baseline)
        │
        ▼
Cost Anomaly Monitor  (all services, DIMENSIONAL)
        │  anomaly > $10 above expected
        ▼
SNS Topic: raw-anomaly          ← costalerts.amazonaws.com publishes here
        │
        ▼
Lambda: cost-alerter            ← formats JSON → readable email
        │
        ▼
SNS Topic: cost-alert
        │
        ▼
Email → your-email@example.com
```

## Services

| Service | Purpose |
|---|---|
| AWS Cost Anomaly Detection | ML-based spend monitoring across all services |
| SNS (x2) | Raw anomaly delivery + formatted alert delivery |
| Lambda (Python 3.12) | Parses raw payload, formats human-readable email |
| IAM | Least-privilege role for Lambda |
| CloudWatch Logs | Lambda execution logs (14-day retention) |
| HCP Terraform | State management + VCS-driven CI/CD |

## Security

- No static AWS credentials — HCP uses OIDC dynamic credentials
- Lambda has least-privilege IAM (SNS:Publish + CloudWatch only)
- SNS topic policy explicitly scopes `costalerts.amazonaws.com` as publisher
- `terraform.tfvars` gitignored — never committed
