# Week 10 — Centralised Logging Platform

**The story:** the org now has multiple accounts, each hoarding its own CloudWatch log groups — and "show me every error across the platform in the last hour" means logging into each account and running the same query N times. This week builds the 2025-era fix: CloudWatch cross-account observability (OAM) for query-in-place, plus the new native Logs Centralization rules for durable copies that survive the account that produced them — no OpenSearch cluster, no Firehose pipeline, near-zero cost.

> **Why no OpenSearch?** AWS is retiring its "Centralized Logging with OpenSearch" solution (December 2026) in favour of CloudWatch-native centralization, and Logs Insights now speaks OpenSearch PPL/SQL directly. A permanently-running cluster (~$26/mo minimum) buys nothing at this log volume.

## Architecture

```
      SOURCE ACCOUNT (spoke)                    MONITORING ACCOUNT (hub)
┌─────────────────────────────┐          ┌──────────────────────────────────┐
│ EventBridge (rate 5 min)    │          │  OAM Sink  ◄──── OAM Link ───────┼── (from spoke)
│        │                    │          │     │  query-in-place: logs +    │
│        ▼                    │          │     │  metrics, no copying       │
│ log_generator Lambda        │          │     ▼                            │
│        │ structured JSON    │          │  CloudWatch Dashboard            │
│        ▼                    │          │  (cross-account widgets)         │
│ /platform-lab/week10/...    │          │                                  │
│  (app log group)            │  copies  │  /platform-lab/week10/...       │
│        └────────────────────┼─────────►│   (centralized copy, 30d)       │
│   org-wide centralization   │  free    │     │ metric filter (ERROR)     │
│   rule (new data only)      │  1st copy│     ▼                            │
└─────────────────────────────┘          │  Alarm ──► SNS ──► email         │
                                         └──────────────────────────────────┘
```

| Service | Role here |
|---|---|
| CloudWatch OAM (sink + link) | Cross-account query-in-place for logs and metrics — $0 |
| CloudWatch Logs Centralization rule | Physical org-wide copy of matching log groups — first copy free |
| CloudWatch Logs Insights | One query across accounts via `@aws.account` / `@aws.region`; PPL/SQL supported |
| Lambda (log generator) | Scheduled, stateless, ms-duration synthetic traffic in the source account |
| EventBridge | Fires the generator every 5 minutes |
| Metric filter + alarm + SNS | ERROR spike in the centralized stream pages by email |
| CloudWatch dashboard | Single pane over both accounts |

## Prerequisites

1. **AWS Organizations trusted access for CloudWatch** must be enabled from the
   management account before centralization rules can be created — there is no
   Terraform resource for this yet. Enable once via Console (CloudWatch →
   Settings → Organization) or CLI, and verify with:
   ```bash
   aws organizations list-aws-service-access-for-organization
   ```
2. A member account (the spoke) reachable from the management account via an
   assumable role (`OrganizationAccountAccessRole` by default — override with
   `source_role_name` if yours differs).
3. HCP Terraform workspace `week-10-dev` (VCS-connected to this repo, working
   directory `week-10-centralized-logging/terraform/environments/dev`) with
   workspace variables `source_account_id` and `alert_email` set, and OIDC
   env vars `TFC_AWS_PROVIDER_AUTH` / `TFC_AWS_RUN_ROLE_ARN` configured.

## Quick Start

```bash
# 1. Package the Lambda
./scripts/deploy.sh

# 2. Commit and push (HCP runs plan remotely on push to main)
git add -f lambda/log_generator/log_generator.zip
git add .
git commit -m "Week 10: centralised logging platform"
git push

# 3. In HCP UI: review the plan on week-10-dev, confirm Apply

# 4. Confirm the SNS email subscription from your inbox

# 5. Watch data arrive (5-10 min for first generator runs + centralized copies)
```

## Cost

| Component | Deployed | Notes |
|---|---|---|
| OAM sink/link | $0 | No charge for logs/metrics sharing |
| Centralization rule (first copy) | $0 ingestion | Extra copies would be $0.05/GB |
| Log storage (both copies) | ~$0.03/GB-mo | Bounded: 14d source / 30d central retention |
| Lambda + EventBridge | ~$0 | Well inside free tier |
| SNS email | ~$0 | First 1,000 notifications free |
| **Total** | **< $2/mo** | **Destroyed: $0** |

Prices as of July 2026 — verify at aws.amazon.com/cloudwatch/pricing/.

## Security Patterns

- OAM sink policy is scoped to the organization ID and to logs/metrics only —
  no account outside the org can link, and linked accounts can't share other
  resource types.
- Centralized copies live in an account the source account cannot modify —
  log evidence survives source-account compromise or deletion.
- Cross-account deploy uses a role assumption from the management account; no
  static credentials anywhere (HCP itself authenticates to AWS via OIDC).
- Generator Lambda's IAM role can write only to its own log group.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `terraform plan` fails on the centralization rule | Organizations trusted access for CloudWatch not enabled (Prerequisite 1) |
| Centralized log group stays empty | Rule only copies data written *after* rule creation; wait for the next generator run |
| No alarm emails | SNS subscription not confirmed — check inbox for the confirmation link |
| Dashboard cross-account widgets empty | OAM link not established or metrics not shared — check CloudWatch → Settings in both accounts |
| Assume-role error on spoke resources | `source_role_name` doesn't exist in the source account — set the variable to a role the management account can assume |

## Blog

Post URL added after publish.
