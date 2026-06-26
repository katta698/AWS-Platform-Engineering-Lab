# Week 07 — IAM Identity Center SSO (Multi-Account Permission Sets)

**The story:** Week 6 built an Account Vending Machine — a ServiceNow ticket now produces a real AWS account inside the right Organizational Unit in minutes, with SCP guardrails attached automatically. But that just answers "where does the account live." It doesn't answer "who can actually log into it, and with what level of access." Today that gap is filled by hand: someone creates an IAM user or role per account, per person, and quietly accumulates long-lived credentials and inconsistent permissions across every account in the Organization. This week closes that gap with **IAM Identity Center** — one set of users and groups, a small number of reusable permission sets (least-privilege role definitions), and account assignments that let AWS provision the actual IAM role into every target account automatically. Add someone to the `Engineers` group once, and they can federate into every Sandbox and Production account vended so far — no per-account IAM user, no long-lived access keys.

---

## What It Builds

- **Permission sets** — `ReadOnlyAuditors`, `Engineers`, `BreakGlassAdmins`, each backed by an AWS managed policy and its own session duration (shorter for the admin permission set)
- **Identity Store groups** — one per permission set, created in the Identity Center-managed identity store
- **Identity Store users** — a couple of test users, created and added to a group via Terraform
- **Account assignments** — every group × every account in Week 6's `Sandbox`/`Production` OUs, which causes AWS to provision the matching `AWSReservedSSO_*` IAM role into each target account automatically

---

## Architecture

```
terraform.tfvars: groups{} + users{}
        ↓
Terraform (identity-center module)
        ↓
  ┌────────────────────────────────────────────────────┐
  │ 1. aws_ssoadmin_permission_set      (per group)     │
  │ 2. aws_ssoadmin_managed_policy_attachment            │
  │ 3. aws_identitystore_group           (per group)     │
  │ 4. aws_identitystore_user            (per test user) │
  │ 5. aws_identitystore_group_membership                │
  │ 6. aws_ssoadmin_account_assignment   (group x account)│
  └────────────────────────────────────────────────────┘
        ↓
AWS auto-provisions AWSReservedSSO_<permission-set>_* role
into every Sandbox/Production account from Week 6
        ↓
User signs in once via the Identity Center portal,
picks an account + role, gets temporary federated credentials
```

---

## Key AWS Services

| Service | Role |
|---------|------|
| IAM Identity Center | SSO portal, permission sets, account assignments |
| Identity Store | Users and groups backing the Identity Center instance |
| AWS Organizations | Source of the target accounts (reused from Week 6's OUs) |
| IAM | The actual `AWSReservedSSO_*` roles Identity Center provisions per account |

---

## Manual Prerequisite — Enable IAM Identity Center

There is no Terraform resource to create the IAM Identity Center instance itself — only to manage permission sets and assignments once it exists. Before the first apply:

1. AWS Console (management account) → **IAM Identity Center** → **Enable**
2. Choose the **Organization** instance type (not Account instance type) so assignments can target every member account
3. Note the Identity Store ID and instance ARN — Terraform looks these up automatically via `aws_ssoadmin_instances`, so no need to hardcode them

Do this once. Everything after it is Terraform-managed.

---

## Prerequisites

- IAM Identity Center enabled per the manual step above
- Must be deployed with credentials for the Organizations **management account**
- Week 6's Account Vending Machine already applied — this week looks up accounts in its `Sandbox`/`Production` OUs by name (`parent_ou_name` / `target_ou_names` in `terraform.tfvars`)
- State is in **HCP Terraform** — org: `Katta` | workspace: `week-07-dev`
- Terraform >= 1.10

### Deviation actually used for end-to-end testing

Validating this module against a live account required two adjustments not implied by the design above:

- **`target_ou_names` overridden to `["Dev"]`** — at the time of testing, Week 6's `Sandbox`/`Production` OUs were empty (no account had been vended through that pipeline yet). An older `Dev` OU already had one active account (`ent-wkld-dev-sandbox`), so `target_ou_names` was pointed there instead, as an HCP workspace variable override, purely to exercise the assignment logic against something real. Revert to the default `["Sandbox", "Production"]` once accounts actually exist in those OUs.
- **Identity Center MFA enforcement relaxed** — "If a user does not yet have a registered MFA device" was switched from the default **"Require them to register an MFA device at sign in"** to **"Allow them to sign in"**, because the Terraform-created test user has no MFA device and no self-service registration path surfaced during sign-in (cause not fully diagnosed — possibly tied to sign-in state cached from an earlier blocked attempt). This is a real security trade-off, not cosmetic — **revert to requiring MFA registration before using this with real users/production accounts.**

---

## Deploy Steps

`week-07-dev` is a **VCS-connected HCP Terraform workspace** (same pattern as Weeks 5–6) — Terraform runs remotely from this GitHub repo, not from local CLI.

```bash
bash scripts/deploy.sh   # pre-deploy checklist (Identity Center enabled? real emails set?)
```

Copy `terraform/environments/dev/terraform.tfvars.example` to `terraform.tfvars` (gitignored), set real, unique email addresses for each test user, then:

```bash
git add -A
git commit -m "Configure Week 7 SSO users/groups"
git push
```

Then in the HCP UI: **week-07-dev → Start new plan**, review, and confirm **Apply**.

Note: local `terraform apply`/`destroy` against this workspace will fail with `Saved plans not allowed for workspaces with a VCS connection` — that's expected; all applies/destroys go through the HCP UI.

### Verifying the assignment

After apply, sign in to the Identity Center **AWS access portal** URL (shown in the Identity Center console) as one of the test users — they'll see every target account they're assigned to, scoped down to only the permission sets their own group membership grants. In testing, all three permission sets (`Engineers`, `ReadOnlyAuditors`, `BreakGlassAdmins`) were assigned to the target account, but the test user (a member of only the `Engineers` group) saw just that one role in the portal — confirming the scoping works per-user, not per-account.

Identity Center users created via Terraform have no password and no MFA device by default — there's no Terraform-side equivalent of "send invite email." Use **Reset password** (admin-initiated, on the user's detail page) to get a usable credential for testing, not the self-service "Forgot password?" flow on the portal sign-in page, which surfaced a stuck MFA-required error in testing that the reset-password path avoided.

---

## Cleanup

Destroy must be confirmed from the **HCP UI** (same VCS-connection restriction as deploy) — `bash scripts/cleanup.sh` just walks through the pre-destroy checklist and waits for confirmation; it does not call `terraform destroy` itself. Trigger the actual destroy from **week-07-dev → Settings → Destruction and Deletion → Queue destroy plan**, then confirm Apply.

A destroy run removes the permission sets, groups, users, and account assignments — it does **not** disable IAM Identity Center itself, since enabling it was a manual, one-time console step outside Terraform's control.

---

## Security

- Permission sets use AWS managed policies scoped to the access level needed (`ReadOnlyAccess`, `PowerUserAccess`, `AdministratorAccess`) rather than one shared admin role for everyone
- `BreakGlassAdmins` uses the shortest session duration (`PT1H`) of the three, by design — full-admin access should expire fastest
- No long-lived IAM users or access keys created in any target account — Identity Center issues temporary federated credentials per session
- `terraform.tfvars` gitignored — never committed (contains real user emails)

---

## Cost

| Resource | Cost |
|----------|------|
| IAM Identity Center | Free |
| Permission sets, groups, users, assignments | Free |
| IAM roles auto-provisioned into target accounts | Free |
| **Destroyed** | **$0** |

---

## Blog

Published: [Week 7 — IAM Identity Center SSO: Multi-Account Permission Sets](https://jayanthkatta.com/blog/week-7-iam-identity-center-sso-multi-account-permission-sets/)
