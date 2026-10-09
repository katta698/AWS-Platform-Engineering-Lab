# Week 22 — Container Image Security Pipeline

**The goal, in one sentence:** no container image can be deployed unless this
pipeline signed it and a scanner cleared it — and both facts are provable for
any image in the registry afterwards.

Three controls do three different jobs, and the week exists to show that the
third one is the only one that stops anything:

| Control | Question it answers | Does it block anything? |
|---|---|---|
| ECR managed signing | **Who** pushed this image? | No — it writes a signature |
| Amazon Inspector enhanced scanning | **What known flaws** does it contain? | No — it writes findings |
| The gate (Lambda) | **Should this be deployable?** | Yes. This is the only enforcing part |

Most writing on this topic stops after the first two and calls it a pipeline.

---

## Before you start

| | |
|---|---|
| Terraform | >= 1.10 |
| AWS provider | >= 6.67 — see the note on the signing resource below |
| AWS CLI | >= 2.34 (`ecr get-signing-configuration` and friends are recent) |
| Docker | **Not needed.** Images are built in CodeBuild — see step 7 |
| HCP Terraform | An org you can create a workspace in, with OIDC to AWS |
| Inspector | **Not already enabled.** Check first: the free trial is once per account |

```bash
# Is Inspector already on? All five should read DISABLED before you begin.
aws inspector2 batch-get-account-status \
  --query 'accounts[0].resourceState' --output table

# What scanner is the registry using now? Expect BASIC.
aws ecr get-registry-scanning-configuration \
  --query 'scanningConfiguration.scanType' --output text
```

**Amazon Inspector is a separate AWS service with its own bill.** ECR's
"enhanced scanning" setting does not add a feature to ECR — it hands scanning
to Inspector. You flip it in the ECR console and the charges appear under
Inspector. That is the single most confusing thing about this week.

---

## The order

Eight steps. Each one ends with a check, because a step you cannot verify is a
step you cannot debug later.

### 1. Look at the starting state — *console*

Open **ECR → Private registry → Features & settings** and **Inspector**. Both
should be in their default state. Capture it: a post that shows the end state
only is impossible to follow.

→ *Figure 01.* **Check:** scanning reads `BASIC`, Inspector reads disabled.

### 2. Write the Terraform — *laptop*

```
terraform/
  environments/dev/     # backend, providers, the module call
  modules/image_pipeline/
lambda/image_gate/handler.py
docker/{clean,vuln-os,vuln-lib}/
```

**The one thing that will surprise you.** ECR managed signing shipped on
21 November 2025 and still has **no resource in the AWS provider** —
[hashicorp/terraform-provider-aws#47527](https://github.com/hashicorp/terraform-provider-aws/pull/47527)
is still open, and 6.68.0 shipped on 7 October 2026 without it. Confirm it
yourself rather than trusting this file:

```bash
terraform validate
# Error: Invalid resource type ... does not support "aws_ecr_signing_configuration"
```

Cloud Control has the resource, so the feature is still manageable
declaratively today:

```hcl
resource "awscc_ecr_signing_configuration" "registry" {
  rules = [{
    signing_profile_arn = aws_signer_signing_profile.images.arn
    repository_filters  = [{ filter = "wk22-*", filter_type = "WILDCARD_MATCH" }]
  }]
}
```

Two traps in the schemas:

- Signing profile names accept `[a-zA-Z0-9_]` only. `wk22-signer` is rejected;
  `wk22_signer` is fine. Use `name_prefix`.
- The scanning filter type is `WILDCARD`; the signing filter type is
  `WILDCARD_MATCH`. Different strings for the same idea.

→ *Figure 02.* **Check:** `terraform fmt` and `terraform validate` both clean.

### 3. Create the HCP workspace — *HCP*

Workspace `week-22-dev`, working directory `terraform/environments/dev`,
AWS credentials via **OIDC** (`TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN`).
Set `alert_email` as a **sensitive** variable so the address is never written
into a file in the repo.

→ *Figure 03.* **Check:** no static access keys anywhere in the workspace.

### 4. Plan, and actually read it — *HCP*

This is the step tutorials skip and nobody skips at work. You are looking for
a resource you did not intend — in particular whether the scanning rule's
filter is narrower than your whole registry.

→ *Figure 04.* **Check:** the count matches what you meant to build.

### 5. Apply — *HCP*

→ *Figure 05.* **Check:** applied, and the outputs give you a repository URL.

### 6. Verify the controls in the console — *console*

Code applying is not the same as a control being on. Look at both:

- **ECR → Private registry → Managed signing** — the rule and its filter
- **ECR → Private registry → Scanning** — `ENHANCED`, with your filter

→ *Figures 06, 07.* **Check:** the console agrees with the code.

### 7. Build the images and test — *CodeBuild, then laptop*

```bash
aws codebuild start-build --project-name week22-imagesec-build
bash scripts/test_gate.sh <stamp>    # runs the six tests in order
```

**The build does not run on your machine, and that is the point.** The ECR
console states it plainly: *"ECR will sign the image using the IAM credentials
of the entity that pushed the image."* Push from a laptop and the signature
attests to a laptop — precisely what image signing exists to replace. Push
from a build role and "signed by my pipeline" is literally true.

The consequence is a permission that is easy to miss: the build role needs
`signer:SignPayload` on the signing profile **as well as** the ECR push
actions. Without it the push still succeeds and the image is simply not
signed — managed signing fails quietly rather than rejecting the push, so a
role that can push but not sign produces unsigned images and no error.

Three images, each isolating one variable:

| Image | Base | Expected |
|---|---|---|
| `clean` | Current Alpine, nothing added | Signed, 0 blocking findings, stays deployable |
| `vuln-os` | Ubuntu 20.04 (end of support, May 2025) | Quarantined on OS findings |
| `vuln-lib` | **Current** Python + `flask==2.0.0` | Quarantined on a **PYTHON** package finding |

`vuln-lib` is the one that justifies the money. ECR's free basic scanner reads
OS packages only; it cannot see an outdated Python, npm or Maven dependency. (Inspector labels the
package manager `PYTHON`, not `PIP` -- the docs show `PIP` in a Lambda example,
and a check grepping for that reports nothing found on a passing test.) Its
base is deliberately current so the only findings come from the library — an
end-of-life Python would produce OS findings too and the experiment would stop
isolating anything.

Every base image is **pinned by digest**. `alpine:3.22` is whatever was
published this morning, so a tag-pinned lab gives different scan results on a
rerun and the write-up stops being reproducible.

→ *Figures 08, 09, 10, 11.*

### 8. Destroy, then verify — *HCP + terminal*

```bash
python ../scripts/hcp_destroy.py week-22-dev   # blocks if figures are missing
bash scripts/cleanup.sh                        # verifies, and undoes what destroy cannot
```

→ *Figure 12.* Cost comes a day later (*Figure 13*).

---

## The tests

Run in order. A failure in test 2 means nothing if test 1 never passed.

| # | Test | Why it earns its place |
|---|---|---|
| 1 | Clean image is signed and stays deployable | The happy path. Also catches a gate that quarantines everything |
| 2 | OS-vulnerable image is quarantined | Enforcement works |
| 3 | **Signed** vulnerable image is still quarantined | **Signing proves provenance, not safety.** A valid signature on a flawed image is the most dangerous false comfort here |
| 4 | Repository outside the filter is neither signed nor scanned | Proves the filter is a real boundary. Every cost control this week rests on it |
| 5 | Time from push to quarantine | Scanning is **asynchronous**. There is a window where an unscanned image is pullable. "We scan on push" is weaker than it sounds, and this measures by how much |
| 6 | Gate fails **closed** on a malformed event | A security control that waves images through when broken is worse than none, because the dashboard stays green |

Tests 3, 5 and 6 are the ones worth the week.

---

## Security decisions, and why

- **OIDC to AWS, no static keys.** HCP assumes a role per run.
- **Immutable tags.** Not a convenience setting — a security control. With
  mutable tags, an image approved as `v1.2.3` can be quietly repointed after
  review, and the signature and scan result then describe something that is no
  longer there.
- **The gate quarantines, never deletes.** The image stays under a
  `quarantined-*` tag; only the deployable tag is removed. Deleting destroys
  the evidence needed to answer "what shipped, and when did we know". An
  incident review cannot run on an empty repository.
- **The gate fails closed and alarms on its own errors.** A gate that stops
  working silently leaves every later push unenforced.
- **Least privilege.** The gate's policy names the two repository ARNs and the
  one topic. The single `Resource: "*"` is on `inspector2:ListFindings`, which
  is not resource-scopable — stated rather than hidden.
- **The signing key is not yours.** A Signer profile takes a platform, a
  validity period and tags — and no key of any kind. For container signing,
  Signer generates and holds the key material itself. You control *who may ask
  it to sign* via `signer:SignPayload`; you never touch the key, cannot export
  it, and cannot rotate it on your own schedule. That is a trust decision, not
  an absence of one.

## Cost control

- Scanning and signing are **scoped by repository filter**, not registry-wide.
  A registry-wide rule would also scan unrelated repositories in the account —
  and Inspector bills per image.
- A **lifecycle policy expires untagged images**. Under continuous scanning
  every retained image is re-scanned each time the CVE database updates, so an
  image nobody can deploy is a recurring charge rather than a one-off.
- `SCAN_ON_PUSH`, not `CONTINUOUS_SCAN`. Continuous is the right production
  choice and the wrong one for a lab that lives for a few hours.
- Teardown **explicitly disables Inspector**. It is enabled per *account*, so
  no stack owns it and `terraform destroy` cannot be relied on to remove it.
  Week 14 proved this shape of risk when anomaly detectors survived a destroy
  and kept billing.

## What production does differently

Written down rather than silently skipped:

- ~~Build in CI, not on a laptop.~~ **Done here** — see step 7. It was
  written up as a production delta and became the real path when the lab
  machine turned out to have no WSL distribution, so Docker could not run
  locally at all. The better design won by accident, which is worth admitting.
- **A customer-managed KMS key on the repository.** ~$1/month, and it buys a
  second lock independent of IAM plus an audit trail of every decrypt. This
  lab uses ECR's default `AES256` because the key would cost ten times the
  rest of the week.
- **`CONTINUOUS_SCAN`**, so an image already in the registry is re-examined
  when a new CVE lands. Most real incidents of this kind involve an image that
  was clean on the day it was pushed.
- **Verification at deploy time**, not just quarantine after the fact. ECS does
  not verify signatures natively; on EKS an admission controller does it with
  the Notation verifier.

## References

- [ECR managed signing](https://docs.aws.amazon.com/AmazonECR/latest/userguide/managed-signing.html)
- [ECR enhanced scanning](https://docs.aws.amazon.com/AmazonECR/latest/userguide/image-scanning-enhanced.html)
- [Inspector EventBridge event schema](https://docs.aws.amazon.com/inspector/latest/user/eventbridge-integration.html)
- [AWS Signer pricing](https://docs.aws.amazon.com/signer/latest/developerguide/whatis-pricing.html)
- [`AWS::ECR::SigningConfiguration`](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-resource-ecr-signingconfiguration.html)

## Cost

**Billed $0.2409**, and 99.7% of it was signing.

| Line | Cost |
|---|---|
| ECR managed signing — 12 signatures at $0.02 | $0.2400 |
| ECR storage, 6-9 October | $0.0009 |
| Amazon Inspector | $0.00 — 15-day free trial, started 2026-10-05, expires 2026-10-20 |
| CodeBuild, Lambda, EventBridge, SNS | $0.00 — free tier |

**ECR bills managed signing at $0.02 per signature**, as usage type
`AsyncActions-ImageSigning`. AWS Signer's pricing page says "no additional
charge" and is correct about Signer; the charge is on ECR's side, and the ECR
pricing page carries a "Managed Signing" heading with no figure under it. The
bill was the only place the number appeared.

Twelve signatures rather than three, because **every rebuild re-signs**. Four
builds during one night of debugging cost four times a single build. On a busy
pipeline that is the line to watch, not storage — which came to eight
hundredths of a cent.

## Teardown

**Destroyed 2026-10-09**: 24 resources via HCP run `run-UcvQxgEL4N2Ym11T`, then
`scripts/cleanup.sh` verified the account-level state.

| Checked | Result |
|---|---|
| Registry scanning | `BASIC` |
| Inspector — all five scan types | `DISABLED` |
| ECR repositories | none remaining |
| Signer signing profiles | none active |
| Signing configuration | none |
| Log groups | none remaining |

Worth recording: **`terraform destroy` had already removed the Inspector
enabler and the scanning configuration** — the cleanup script found both
already clean, with no "still enabled" branch taken. In this build they are
Terraform resources, so destroy owns them. The script still checks, because
account-level settings are where an unowned leftover bills quietly, but the
risk here was smaller than anticipated.
