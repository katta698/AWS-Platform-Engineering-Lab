# Week 12 — AWS Config Compliance Automation

**The story:** Security Hub (Week 11) only catches *security* misconfigurations
— it has no concept of governance drift like a missing cost-allocation tag or
a data bucket that was never versioned. Those don't trip any alarm; they just
accumulate until a finance report has unattributed spend, or a bucket loses
data with no way back. This week adds three AWS Config rules for exactly that
gap, bundled into a single conformance pack: two auto-remediate through
AWS-managed SSM Automation documents (tag-scoped opt-in, same guardrail
philosophy as Week 11), and a tagging-governance rule that's notify-only,
because a tag value can't be safely invented by automation.

## Architecture

```
        ┌───────────────────────────────────────────────────────────┐
        │             Conformance Pack (week12-cfgcompliance-pack)    │
        │  self-contained: defines its own rules + remediations       │
        │                                                              │
        │   required-tags            s3-versioning       s3-sse       │
        │   (environment,             -enabled            -enabled     │
        │    owner, cost-center)      scope: tag=          scope: tag=  │
        │   scope: broad              auto-remediate=true  auto-remediate=true
        │        │                        │                   │        │
        │        │ NON_COMPLIANT          │ NON_COMPLIANT      │        │
        │        │ (notify only)          ▼                   ▼        │
        │        │                 ┌─────────────┐    ┌──────────────┐ │
        │        │                 │ SSM Doc:     │    │ SSM Doc:     │ │
        │        │                 │ Configure    │    │ Enable       │ │
        │        │                 │ S3Bucket     │    │ S3Bucket     │ │
        │        │                 │ Versioning   │    │ Encryption   │ │
        │        │                 └──────┬───────┘    └──────┬───────┘ │
        │        │                        │  assumes SSM automation role│
        └────────┼────────────────────────┼────────────────────┼────────┘
                  │                        ▼                    ▼
                  │                 versioning ON          SSE (AES256) ON
                  ▼
        ┌──────────────────────────────────────────────────────────────┐
        │  compliance_reporter (Lambda, daily EventBridge schedule)      │
        │  GetComplianceDetailsByConfigRule for these 3 rules only        │
        │  (never the account's ~300 securityhub-* rules)                  │
        └───────────────────────────┬──────────────────────────────────┘
                                     ▼
                     SNS digest topic → email
        failed reporter invoke ─▶ SQS DLQ (14-day) ─▶ CloudWatch alarm ─▶ SNS
```

This stack provisions its own Config recorder (`module.config_recorder`) —
a delivery-channel S3 bucket, an IAM role, and the recorder itself, recording
`ALL_SUPPORTED_RESOURCE_TYPES` continuously. This wasn't the original plan:
the account initially had a centrally-managed recorder from an unrelated
project, which this week reused. That recorder was deleted 2026-07-29 as
part of that other project's own cleanup — confirmed via CloudTrail, not
caused by this stack. Losing it also silently broke Week 11's Security Hub
FSBP controls (which are backed by Config), since without an active recorder
those controls sit at `NO_DATA`. This Lab now owns its recorder going
forward; Week 11 needed no changes of its own to benefit from it.

## Why a conformance pack, not standalone `aws_config_config_rule` resources

A conformance pack is self-contained: its template *defines* its own
`AWS::Config::ConfigRule` / `AWS::Config::RemediationConfiguration` resources
rather than wrapping rules created elsewhere. So the 3 rules here exist only
inside the pack — there are no separate standalone Config-rule Terraform
resources duplicating them. That also makes the pack's own console
compliance-% view the real "Compliance Dashboard" this week set out to build,
not a second copy of something that already exists.

## Why these 3 rules, specifically

The account already has ~300 Config rules (`securityhub-*`) auto-created by
Security Hub's FSBP standard (Week 11) — nearly every security-relevant check
already exists. Adding more of those would be redundant, not just repetitive.
`required-tags`, `s3-bucket-versioning-enabled`, and
`s3-bucket-server-side-encryption-enabled` are confirmed absent from that set:
FSBP's S3 checks are public-access and SSL-in-transit only, and it has no
tagging-governance concept at all.

## Services

| Service | Role in this build |
|---|---|
| AWS Config (recorder) | Records configuration changes for every supported resource type, account-wide — this Lab's own, since the account's previous (unrelated-project) recorder was deleted |
| AWS Config (conformance pack) | Defines the 3 rules + 2 remediation configs as one deployable unit |
| AWS Systems Manager Automation | Runs the actual fix — `AWS-ConfigureS3BucketVersioning` / `AWS-EnableS3BucketEncryption`, both AWS-managed documents |
| AWS IAM | Role SSM Automation assumes to call `s3:PutBucketVersioning` / `s3:PutBucketEncryption`, scoped by `aws:ResourceTag` |
| AWS Lambda | `compliance_reporter` — daily digest of just these 3 rules' compliance status |
| Amazon EventBridge | Daily schedule triggering the reporter |
| Amazon SNS | Delivers the compliance digest to a subscribed email |
| Amazon SQS | Dead-letter queue for failed reporter invocations |
| Amazon CloudWatch | Reporter logs + an alarm when the DLQ is non-empty |

## Rules and remediation

| Rule | Scope | Action | Guardrail |
|---|---|---|---|
| `week12-required-tags` | All S3 buckets, EC2 instances, EBS volumes | None — notify only, via the next daily digest | A tag value (`cost-center`, etc.) can't be safely invented |
| `week12-s3-bucket-versioning-enabled` | S3 buckets tagged `auto-remediate=true` | `AWS-ConfigureS3BucketVersioning` enables versioning | Config `Scope.TagKey/TagValue` **and** IAM `aws:ResourceTag` condition both restrict to opted-in buckets |
| `week12-s3-bucket-sse-enabled` | S3 buckets tagged `auto-remediate=true` | `AWS-EnableS3BucketEncryption` enables AES256 default encryption | Same double guardrail as above |

Names above are the base names declared in the conformance pack template. AWS
Config appends its own generated suffix to the actual deployed rule (e.g.
`week12-required-tags-conformance-pack-<id>`) — found live on the first
apply. Use `aws configservice describe-conformance-pack-compliance
--conformance-pack-name week12-cfgcompliance-pack` to see the real names;
the `compliance_reporter` Lambda discovers them the same way rather than
hardcoding them.

## Recorder ownership — check before deploying elsewhere

Without an active Config recorder, these rules (and Week 11's Security Hub
FSBP controls) report `NO_DATA` and nothing evaluates. This stack provisions
its own recorder (see Architecture above), so no external prerequisite is
needed here — but if this Lab is ever deployed into an account that already
has a recorder from another project, **do not apply this stack as-is**: AWS
allows only one recorder per account/region, so a second `aws_config_configuration_recorder`
resource will fail. Check first:

```bash
aws configservice describe-configuration-recorder-status \
  --query 'ConfigurationRecordersStatus[].[name,recording,lastStatus]' --output text
```

If one already exists, remove `module.config_recorder` from `main.tf` and
point the other modules at the existing recorder instead.

## Quick start

This deploys via **HCP Terraform** (workspace `week-12-dev`, VCS-driven). HCP
runs plan/apply remotely from the GitHub repo — there is no local
`terraform apply` and no GitHub Actions workflow (a VCS-connected workspace
blocks CI applies).

1. **Set the workspace variable** `alert_email` (sensitive) in HCP to the
   address that should receive the daily digest.
2. **Build + commit the reporter Lambda zip** (HCP can't build it):
   ```bash
   cd week-12-config-compliance-automation
   ./scripts/build_lambdas.sh
   git add -f lambda/**/*.zip
   git commit -m "Week 12: compliance reporter lambda" && git push
   ```
3. **Apply** in the HCP UI: start a plan on `week-12-dev`, review, confirm apply.
4. **Confirm the SNS subscription** — click the link in the confirmation email.
5. **Exercise it end-to-end:**
   ```bash
   ./scripts/generate_misconfig.sh
   ```
   Creates an opted-in bucket (no versioning/encryption — should auto-fix
   within minutes) and an untagged bucket (should surface in the next daily
   digest). Config evaluates on a resource-change trigger, usually within a
   few minutes.

## Configuration

All knobs are workspace/`tfvars` variables (see `terraform.tfvars.example`):
`remediation_tag_key`/`value` (opt-in gate, default `auto-remediate`/`true`),
`required_tag_keys` (exactly 3 — default `environment`, `owner`,
`cost-center`), `log_retention_days`.

## Security patterns

- **Tag-scoped opt-in, enforced twice.** The two S3 rules only evaluate
  tagged buckets (Config's native `Scope.TagKey`/`TagValue`), and the SSM
  automation role's IAM policy adds the same `aws:ResourceTag` condition —
  the API refuses the call even if a rule were ever mis-scoped.
- **Native remediation substrate, not custom code.** Both fixes use
  AWS-managed SSM Automation documents (verified live against this account),
  not a bespoke Lambda — a single documented API call needs nothing more.
- **Notify, never invent.** `required-tags` never auto-tags a resource; a
  human has to supply the actual `cost-center` value.
- **No silent failures.** Failed reporter invocations land in a 14-day DLQ
  that alarms to SNS.

## Cost

Single low-traffic account, us-east-1. Prices as of July 2026 — verify at
[aws.amazon.com/config/pricing](https://aws.amazon.com/config/pricing/).

| Item | Estimate |
|---|---|
| Config rule evaluations (3 rules, $0.001/eval, well under the 100k tier) | pennies / month |
| Conformance pack evaluations ($0.001/eval) | pennies / month |
| Lambda + EventBridge + SNS + SQS | pennies (well within free tier) |
| Config recorder — configuration items ($0.003/item, continuous, `ALL_SUPPORTED_RESOURCE_TYPES`, account-wide) | not free — this Lab now owns the account's only recorder, replacing the deleted one, so it bills for the whole account's resource inventory, not just this week's own resources. Rough estimate a few dollars/month depending on total resource count and change frequency across every week's deployed infra; monitor actual usage after a few days |
| S3 delivery bucket (config history, 90-day lifecycle expiry) | pennies |
| **Destroyed** | **$0** for this week's own resources; destroying `module.config_recorder` also removes the account's only recorder — re-check before destroying if other weeks still depend on it |

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| Rules show `NO_DATA` | No Config recorder is actively recording — see Prerequisite above |
| Bucket not auto-fixed | Not tagged `auto-remediate=true`, or the tag was added after the rule's last evaluation cycle |
| `PutBucketVersioning`/`PutBucketEncryption` AccessDenied | Expected on untagged buckets — the IAM condition blocks it by design |
| No SNS digest email | Confirm the subscription (one-time click), or wait for the next daily schedule |
| DLQ alarm fired | The reporter Lambda raised — inspect the DLQ message and its CloudWatch logs |

## Cleanup

Queue a destroy plan on `week-12-dev` in the HCP UI. **This removes the
account's only Config recorder along with everything else** (conformance
pack, reporter Lambda/schedule/SNS/DLQ, SSM automation role, the recorder
itself and its delivery bucket) — check first whether Week 11's Security Hub
FSBP controls (or any other future week) still needs a recorder before
destroying this stack; if so, keep `module.config_recorder` and only remove
`module.config_compliance`/`module.reporter`. Remove any leftover test
buckets with `./scripts/cleanup.sh <remediate-bucket> <untagged-bucket>`.

## Blog

Published walkthrough: _(link added on publish)_
