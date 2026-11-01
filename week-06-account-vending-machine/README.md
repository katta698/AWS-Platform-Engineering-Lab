# Week 06 — Account Vending Machine (Simulated, No Control Tower)

**What you build:** A ServiceNow ticket in, an account in the right OU with its guardrail already attached out, and the ticket closed with the new account id.

**The story:** A team lead submits a ServiceNow ticket: "I need a new sandbox AWS account for my team." Today that means a cloud engineer manually creates the account, attaches the right guardrails, and emails back the account ID — minutes of clicking repeated every time someone needs an account. This week automates it: the ticket triggers Step Functions, which creates a real AWS account inside the Organization, places it in the right Organizational Unit, and the SCPs already attached to that OU apply automatically — no manual guardrail setup per account.

This is a **simulated** Account Vending Machine — it builds the same core pattern (Organizations + SCPs + programmatic account creation) that AWS Control Tower's Account Factory provides, without enabling Control Tower itself. Control Tower's managed Landing Zone (dedicated Log Archive/Audit accounts, org-wide CloudTrail) is a heavy, largely irreversible setup — not a fit for a personal lab account meant to be built and torn down weekly.

---

| | |
|---|---|
| **Cost** | ~$0 &mdash; Organizations and SCPs are free, Step Functions under $0.001 per vend |
| **Provisioning** | 100% IaC (Terraform) |

> **Status:** built and validated.

## 1. Prerequisites

### Prerequisites
- Must be deployed with credentials for the Organizations **management account** — `organizations:CreateAccount` and `organizations:MoveAccount` only work there
- State is in **HCP Terraform** (not S3) — org: `Katta` | workspace: `week-06-dev`
- Terraform >= 1.10
- Confirm the existing `Workloads-OU` ID/name before first apply — this Organization already
  has real accounts and Control-Tower-residue OUs at root; the vending OUs nest under
  `Workloads-OU` rather than root (see `parent_ou_name` in `terraform.tfvars`)

---

## 2. Source files

What builds this. Documentation, figures and build artefacts are left out.

```
lambda/account_creator/
  handler.py
lambda/account_mover/
  handler.py
lambda/status_notifier/
  handler.py
lambda/webhook_receiver/
  handler.py
scripts/
  cleanup.sh
  deploy.sh
  test_webhook.sh
terraform/environments/dev/
  main.tf
  outputs.tf
  terraform.tfvars.example
  variables.tf
terraform/modules/api-gateway/
  main.tf
  outputs.tf
  variables.tf
terraform/modules/iam/
  main.tf
  outputs.tf
  variables.tf
terraform/modules/lambda/
  main.tf
  outputs.tf
  variables.tf
terraform/modules/organizations/
  main.tf
  outputs.tf
  variables.tf
terraform/modules/scp/
  main.tf
  outputs.tf
  variables.tf
terraform/modules/step-functions/
  main.tf
  outputs.tf
  variables.tf
```

## 3. Deploy

### Deploy Steps
`week-06-dev` is a **VCS-connected HCP Terraform workspace** (same pattern as Week 5) — Terraform runs remotely from this GitHub repo, not from local CLI. ServiceNow creds, the webhook secret, and AWS auth (dynamic OIDC via `hcp-terraform-role`) are configured as HCP workspace variables, not a local `terraform.tfvars`.

```bash
bash scripts/deploy.sh   # rebuilds the 4 Lambda zips
git add lambda/*/*.zip
git commit -m "Update Lambda packages"
git push
```

Then in the HCP UI: **week-06-dev → Start new plan**, review, and confirm **Apply**. This creates the OUs, SCP, and vending pipeline — **it does not vend any accounts on its own.**

Note: local `terraform apply`/`destroy` against this workspace will fail with `Saved plans not allowed for workspaces with a VCS connection` — that's expected; all applies/destroys go through the HCP UI.

### Triggering an account-vend (read this first)

Submitting a webhook request creates a **real AWS account** in your Organization. There is no instant way to delete it — closing an account puts it into a ~90 day suspension window, not immediate removal, and each account needs a unique email address. Only trigger this deliberately, e.g. with a throwaway alias email, when you actually want to exercise the full pipeline end-to-end.

```bash
# Example payload — see lambda/webhook_receiver/handler.py for required fields
curl -X POST "$API_GATEWAY_URL" \
  -H "Content-Type: application/json" \
  -H "x-servicenow-hmac: sha256=<computed-hmac>" \
  -d '{
        "ticket_id": "RITM0010001",
        "requested_by": "jay",
        "account_name": "sandbox-test-01",
        "account_email": "your-alias+sandbox01@example.com",
        "target_ou": "Sandbox"
      }'
```

---

## 4. Run it

```bash
./scripts/test_webhook.sh
```

Usage: bash test_webhook.sh <api_gateway_url> <webhook_secret> [ticket_id] <account_email> [target_ou] account_email is REQUIRED and has no default: a vended account is a real AWS account tied to a real mailbox, so the address has to be a deliberate choice rather than whatever was left in the script.

## 5. Validation

| Test | Expected |
|---|---|
| The OU tree is created | Sandbox and Production nested under the existing Workloads OU |
| The guardrail is attached | `sandbox-guardrail-scp` attached to the Sandbox OU |
| The webhook authenticates and starts the workflow | An HMAC-signed POST returns 200 and a Step Functions execution ARN |
| An account is vended | A new account appears in the Sandbox OU |
| The failure path reports the failure | `CreateAccount`'s Catch routes to `VendingFailed`, which closes the ticket with the reason |
| Teardown removes everything | A clean destroy |

The results recorded when this lab was built are in the article.

## 6. Cleanup

### Cleanup
Destroy must be confirmed from the **HCP UI** (same VCS-connection restriction as deploy) — `bash scripts/cleanup.sh` just walks through the pre-destroy checklist and waits for confirmation; it does not call `terraform destroy` itself. Trigger the actual destroy from **week-06-dev → Settings → Destruction and Deletion → Queue destroy plan**, then confirm Apply.

A destroy run removes the OUs, SCP, Lambda, Step Functions, and API Gateway — it does **not** touch any account actually vended through the pipeline, since that account was created dynamically via boto3 and is never in Terraform state. AWS also refuses to delete a non-empty OU, so any vended test accounts must be moved out (or closed) via the Organizations console before destroying.

---

## Cost

| Resource | Cost |
|----------|------|
| AWS Organizations, OUs, SCPs | Free |
| Step Functions (per execution) | ~$0.025 per 1,000 state transitions |
| Lambda | Well within free tier |
| API Gateway | Free tier covers low request volume |
| Vended AWS accounts | No direct cost, but each account is real and persists — not destroyed by `terraform destroy` |
| **Pipeline infra destroyed** | **$0** (vended accounts are a separate, manual cleanup) |

---

## Troubleshooting

**The organization was not the blank slate the module assumed**.
It already held Control-Tower-style OUs and three `SUSPENDED` accounts, residue of a decommissioned Landing Zone.
*Fix:* Nested the new OUs inside the existing `Workloads-OU`, found by data source rather than assumed.

**The workspace failed with `lstat ../../modules: no such file or directory`**.
A CLI-driven HCP workspace uploads only the directory Terraform runs from, so a module source above it can never resolve.
*Fix:* Connected the workspace to the repository instead, with `working-directory` set to the environment path.

**Attaching the SCP failed with `PolicyTypeNotEnabledException`**.
`SERVICE_CONTROL_POLICY` had never been enabled on the root, and Terraform creates the policy quite happily while the type is off.
*Fix:* `enable-policy-type`, once. The provider has no equivalent resource.

**When account creation failed, the execution reported `FAILED` and the ticket was never told**.
`VendingFailed` read `$.status_result.failure_reason`, which only the polling branch sets. With `CreateAccount` itself failing, the field did not exist and the handler died on `States.Runtime`.
*Fix:* A `NormalizeFailure` pass state that both Catch blocks route through, mapping `$.error.Cause` into the expected field.

**The first end-to-end test returned `ConstraintViolationException: You have exceeded the allowed number of AWS accounts`**.
Ten accounts against the default limit — seven active, three suspended, and suspended ones still count.
*Fix:* None on the day. Closing an account does not free the slot: it stays suspended for about 90 days before deletion, and counts throughout. The limit moves only by support request.

## References

### Blog
Published: [Week 6 — Building an Account Vending Machine with AWS Organizations, SCPs & Step Functions (No Control Tower)](https://jayanthkatta.com/blog/week-6-account-vending-machine-with-aws-organizations-and-scps/)

## What It Builds

- **Organizational Units** — `Sandbox` and `Production`, nested under the existing `Workloads-OU`
  (this Organization already has real accounts and Control-Tower-style OUs at root — `Core-OU`,
  `Archived-Accounts`, `Workloads-OU` — left over from a previously decommissioned Landing Zone,
  so the vending OUs nest inside `Workloads-OU` rather than sitting alongside that structure)
- **Service Control Policy** — attached to the `Sandbox` OU: denies large/expensive EC2 instance types and restricts activity to allowed regions, automatically inherited by every account moved into that OU
- **Step Functions** — orchestrates the vending pipeline (create → poll → move → notify)
- **Lambda** — ServiceNow webhook receiver, account creator (calls `organizations:CreateAccount`), account mover (moves the new account into its target OU + tags it), status notifier (closes the ServiceNow ticket)
- **API Gateway** — HTTPS endpoint for the ServiceNow webhook

---

## Architecture

```
ServiceNow Ticket (new account request: name, email, target OU)
        ↓
API Gateway (HTTPS + HMAC)
        ↓
Lambda: webhook_receiver
        ↓
Step Functions State Machine
        ↓
  ┌──────────────────────────────────────────┐
  │ 1. organizations:CreateAccount            │
  │ 2. Poll DescribeCreateAccountStatus        │
  │ 3. organizations:MoveAccount → target OU   │
  │ 4. Tag account, update ServiceNow: CLOSED  │
  └──────────────────────────────────────────┘
        ↓
New account now lives inside Sandbox or Production OU
        ↓
SCP guardrails attached to that OU apply immediately — no per-account setup
```

---

## Key AWS Services

| Service | Role |
|---------|------|
| AWS Organizations | Multi-account management, OU hierarchy |
| Service Control Policies (SCP) | Org-level guardrails enforced on every account in an OU |
| Step Functions | Vending pipeline orchestration (create → poll → move → notify) |
| Lambda | Webhook receiver, account creator, account mover, status notifier |
| API Gateway | ServiceNow webhook endpoint |
| IAM | Least-privilege roles scoped per Lambda |

---

## Why Not Real Control Tower

AWS Control Tower is the managed product version of this pattern — it provisions a full Landing Zone (dedicated Log Archive + Audit accounts, org-wide CloudTrail/Config, a polished Account Factory UI) automatically. That's the right choice for a real organization, but enabling it permanently alters the Organization: there's no `terraform destroy` equivalent, decommissioning is a manual multi-step process, and it leaves standing infrastructure behind indefinitely. This project demonstrates the same underlying concepts — Organizations, OUs, SCPs, programmatic account creation — using only resources that can be deployed and torn down like every other week in this lab.

---

## Security

- HMAC-SHA256 signature validation on the ServiceNow webhook (same pattern as prior weeks)
- Each Lambda has a narrowly scoped IAM role (e.g. the account creator can only call `CreateAccount`/`DescribeCreateAccountStatus`, nothing else)
- SCPs enforce guardrails at the Organizations level — they cannot be bypassed by IAM inside the vended account, even by its root user
- `terraform.tfvars` gitignored — never committed

---
