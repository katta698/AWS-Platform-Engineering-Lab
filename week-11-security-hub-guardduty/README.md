# Week 11 — Security Hub + GuardDuty Auto-Remediation

**The story:** a security finding is worthless if it sits in a console nobody
watches. This week wires Security Hub and GuardDuty to EventBridge and Lambda so
the clear-cut, dangerous misconfigurations — a management port open to the whole
internet, a public S3 bucket — get fixed automatically in seconds, while
active-threat findings that need human judgement get escalated to a person
instead of being touched.

## Architecture

```
                 ┌─────────────────┐        ┌──────────────────┐
   FSBP config   │  Security Hub    │        │    GuardDuty     │  active-threat
   findings ───▶ │  CSPM (findings) │        │  (foundational)  │ ◀─── findings
                 └───────┬──────────┘        └────────┬─────────┘
             automation rule                          │
        (escalate prod → CRITICAL,                    │
          fires BEFORE routing)                       │
                         │  "Security Hub              │  "GuardDuty
                         │   Findings - Imported"      │   Finding"
                         ▼                             ▼
                 ┌─────────────────────────────────────────────┐
                 │                 EventBridge                  │
                 │   content-based rules match by control id    │
                 └───┬───────────────┬───────────────────┬──────┘
          EC2.13/14/19        S3.2/3/8              aws.guardduty
                 ▼               ▼                        ▼
        ┌──────────────┐ ┌──────────────┐        ┌────────────────┐
        │ sg_remediator│ │ s3_remediator│        │ threat_notifier│
        │ revoke world-│ │ apply Block  │        │  SNS-notify    │
        │ open ingress │ │ Public Access│        │  (no mutation) │
        └──────┬───────┘ └──────┬───────┘        └───────┬────────┘
   tag-gated:  │ auto-remediate=true               judgement call
   BatchUpdate │ writeback → RESOLVED                    │
               ▼               ▼                          ▼
        ┌───────────────────────────────────────────────────────┐
        │        SNS topic (results + threat alerts) → email     │
        └───────────────────────────────────────────────────────┘
   failed async invoke ─▶ SQS DLQ (14-day retention) ─▶ CloudWatch alarm ─▶ SNS
```

Every automated action is written back to the finding (`BatchUpdateFindings` →
`RESOLVED`/`NOTIFIED`) so Security Hub reflects reality, and every failure lands
in a dead-letter queue that alarms — a dropped security action is worse than a
slow one.

## Why classic Security Hub CSPM (not the unified v2)

AWS re-launched a unified **AWS Security Hub** (v2 APIs) at re:Invent in December
2025 that correlates GuardDuty/Inspector/Macie/CSPM signals. As of mid-2026 the
Terraform AWS provider does **not** yet stably support it (`aws_securityhub_account_v2`
is still an open feature request). v2 is a correlation/analytics layer; the
auto-remediation substrate here — findings → automation rules → EventBridge →
Lambda — is entirely classic **Security Hub CSPM**, which the provider fully
supports. This build uses classic CSPM in Terraform; v2 can be enabled alongside
it in the console for comparison.

## Services

| Service | Role in this build |
|---|---|
| AWS Security Hub (CSPM) | Aggregates FSBP config findings + GuardDuty findings into one ASFF stream |
| Amazon GuardDuty | Foundational threat detection (CloudTrail, VPC Flow Logs, DNS); Extended Threat Detection is auto-enabled at no cost |
| Amazon EventBridge | Content-based routing of findings to the right Lambda / to SNS |
| AWS Lambda | Three functions: two tag-gated auto-remediators + one threat notifier |
| Amazon SNS | Delivers remediation results and threat alerts to a subscribed email |
| Amazon SQS | Dead-letter queue for failed remediations |
| Amazon CloudWatch | Lambda logs + an alarm when the DLQ is non-empty |

## Auto-remediations

| Finding (FSBP control) | Action | Guardrail |
|---|---|---|
| Security group allows `0.0.0.0/0` to SSH/RDP (EC2.13, EC2.14, EC2.19) | Revoke only the world-open ingress on high-risk ports | Only if the SG is tagged `auto-remediate=true` (enforced in code **and** IAM) |
| S3 bucket publicly accessible (S3.2, S3.3, S3.8) | Apply all four Block Public Access settings | Only if the bucket is tagged `auto-remediate=true` |
| GuardDuty threat finding (any type, severity ≥ 4.0) | SNS-notify for human triage — **no mutation** | Active threats are judgement calls; never auto-actioned |

Anything **not** tagged for opt-in is left untouched and a notification is sent
instead, so a human still sees it.

## Quick start

This deploys via **HCP Terraform** (workspace `week-11-dev`, VCS-driven). HCP runs
plan/apply remotely from the GitHub repo — there is no local `terraform apply` and
no GitHub Actions workflow (a VCS-connected workspace blocks CI applies).

1. **Set the workspace variable** `alert_email` (sensitive) in HCP to the address
   that should receive alerts.
2. **Build + commit the Lambda zips** (HCP can't build them):
   ```bash
   cd week-11-security-hub-guardduty
   ./scripts/build_lambdas.sh
   git add -f lambda/**/*.zip
   git commit -m "Week 11: remediation lambdas" && git push
   ```
3. **Apply** in the HCP UI: start a plan on `week-11-dev`, review, confirm apply.
4. **Confirm the SNS subscription** — click the link in the confirmation email.
5. **Exercise it end-to-end:**
   ```bash
   ./scripts/generate_misconfig.sh        # open SG + public bucket → auto-fixed
   ./scripts/trigger_guardduty_sample.sh  # GuardDuty threat → SNS notify
   ```
   Config findings surface in Security Hub within ~15–30 minutes; GuardDuty
   sample findings notify within a minute or two.

## Configuration

All knobs are workspace/`tfvars` variables (see `terraform.tfvars.example`):
`remediation_tag_key`/`value` (opt-in gate), `high_risk_ports` (default `22,3389`),
`guardduty_min_severity` (default `4.0`), `production_tag_key`/`value` (severity
escalation), `finding_publishing_frequency`, `log_retention_days`.

## Security patterns

- **Tag-scoped opt-in.** Mutating remediations only touch resources tagged
  `auto-remediate=true`. The SG remediator enforces this twice: the code checks
  the tag, and its IAM policy adds an `aws:ResourceTag` condition so the API
  refuses `RevokeSecurityGroupIngress` on anything untagged.
- **Least privilege per function.** Each Lambda has its own role scoped to only
  the actions it needs; the notifier has no mutating permissions at all.
- **Surgical revoke.** The SG remediator strips only the `0.0.0.0/0`/`::/0`
  ingress on high-risk ports, leaving legitimate scoped rules in place. It is
  idempotent (an already-removed rule is treated as success).
- **No silent failures.** Failed async invocations go to a 14-day DLQ that
  alarms to SNS. Threat findings are never auto-mutated.
- **Automation rule enrichment.** Failed controls on production-tagged resources
  are escalated to CRITICAL inside Security Hub before any routing happens.

## Cost

Single low-traffic account, us-east-1. Prices as of July 2026 — verify at the
[Security Hub](https://aws.amazon.com/security-hub/pricing/) and
[GuardDuty](https://aws.amazon.com/guardduty/pricing/) pricing pages.

| Item | Estimate |
|---|---|
| GuardDuty foundational (CloudTrail $4/M events, VPC/DNS ~$1/GB) | ~$2–5 / month |
| Security Hub CSPM checks ($0.0010/check; first 10k findings/mo free) | ~$3–15 / month |
| EventBridge + Lambda + SNS + SQS | pennies (well within free tier) |
| **Both services include a 30-day free trial** | covers the lab window |
| **Destroyed** | **$0** |

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| No findings after deploy | FSBP checks take up to ~30 min on first run; GuardDuty finding cadence is `FIFTEEN_MINUTES` |
| Finding appears but SG/bucket not fixed | Resource isn't tagged `auto-remediate=true` — check the SNS "[REVIEW]" email |
| `RevokeSecurityGroupIngress` AccessDenied | Expected on untagged SGs — the IAM condition blocks it by design |
| No SNS emails | Confirm the subscription (one-time click in the confirmation email) |
| DLQ alarm fired | A remediator raised — inspect the DLQ message and the Lambda's CloudWatch logs |
| S3 public bucket policy rejected by an SCP | The BPA finding still fires and remediation still applies — the policy step is only to force the finding |

## Cleanup

Queue a destroy plan on `week-11-dev` in the HCP UI (disables Security Hub CSPM +
GuardDuty, removes the Lambdas/rules/SNS/DLQ). Remove any leftover test resources
with `./scripts/cleanup.sh <sg-id> <bucket-name>`.

## Blog

Published walkthrough: _(link added on publish)_
