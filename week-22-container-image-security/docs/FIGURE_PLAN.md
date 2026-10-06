# Week 22 — Figure plan

Figures are numbered in **work order**, not in the order things were observed.
A reader following the post does these steps in this sequence, and each figure
is the evidence that the step worked.

Week 21 numbered its figures by observation: the HCP apply was `01` and the
Terraform that produced it was `09`. Nobody writes the code after watching it
deploy, so the post read as a tour of outcomes instead of a path to follow.

| # | File | Section | What it shows | Where from |
|---|---|---|---|---|
| 01 | `01-before-state.png` | How We Built It | ECR on BASIC scanning, Inspector disabled on all five scan types — the starting line | AWS console |
| 02 | `02-terraform-layout.png` | How We Built It | The files that build the week, each with its job and line count | Rendered card |
| 03 | `03-hcp-workspace-vars.png` | How We Built It | HCP workspace variables and OIDC — no static keys | HCP |
| 04 | `04-hcp-plan.png` | How We Built It | The plan, read before applying | HCP |
| 05 | `05-hcp-applied.png` | How We Built It | Applied, with the resource count | HCP |
| 06 | `06-ecr-signing-rule.png` | How We Built It | The managed signing rule and its repository filter | AWS console |
| 07 | `07-ecr-scanning-enhanced.png` | How We Built It | Registry scanning on ENHANCED, scoped to the filter | AWS console |
| 08 | `08-push-signed.png` | How We Built It | A push, and `describe-image-signing-status` confirming the signature | Terminal |
| 09 | `09-inspector-language-finding.png` | Challenges | Inspector's findings list — 95 findings, and every impacted resource is already a `quarantined-*` image | AWS console |
| 10 | `10-quarantine-email.png` | Challenges | The quarantine notice as it arrives | Inbox |
| 11 | `11-test-results.png` | Challenges | All six tests with pass/fail, plus the PYTHON-vs-OS finding split that justifies paying for Inspector | Rendered card |
| 12 | `12-destroyed.png` | Cleanup | Zero resources, Inspector back to disabled, scanning back to BASIC | Terminal |
| 13 | `13-cost.png` | Cost | The billed figure | Cost Explorer, ~1 day after teardown |

## Rules carried forward

- Every figure is a **real capture** of a real screen. A typeset card is only
  acceptable where the plan says "Rendered card" — `02` and `11`, neither of
  which has a console equivalent.
- `13-cost.png` cannot exist until roughly a day after teardown, which is why
  the pre-destroy gate treats cost slots as exempt.
- Anything retired goes in `UNUSED.txt` with a reason, not deleted silently.
