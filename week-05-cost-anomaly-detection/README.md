# Week 05 — Cost Anomaly Detection

Automated AWS cost anomaly detection using Cost Explorer ML, SNS, and Lambda.
Deployed and managed via **HCP Terraform** (VCS-driven, org: Katta).


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

## Infrastructure

| Resource | Name |
|---|---|
| Cost Anomaly Monitor | `week05-dev-monitor` |
| Cost Anomaly Subscription | `week05-dev-subscription` |
| SNS Topic (raw) | `week05-dev-raw-anomaly` |
| SNS Topic (alert) | `week05-dev-cost-alert` |
| Lambda | `week05-dev-cost-alerter` |
| IAM Role | `week05-dev-cost-alerter-role` |
| CloudWatch Log Group | `/aws/lambda/week05-dev-cost-alerter` |

## Quick Start

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

## HCP Terraform

State is in HCP (not S3). Org: `Katta` | Workspace: `week-05-dev` | Mode: VCS-driven.
Plan on PR → Apply on merge to main.

## Security

- No static AWS credentials — HCP uses OIDC dynamic credentials
- Lambda has least-privilege IAM (SNS:Publish + CloudWatch only)
- SNS topic policy explicitly scopes `costalerts.amazonaws.com` as publisher
- `terraform.tfvars` gitignored — never committed

## Cost

All resources are within AWS Free Tier or near-zero cost:
- Cost Anomaly Detection: free
- SNS: first 1M publishes/month free
- Lambda: well within free tier
- Destroyed: $0
