# Week 23 — Figure plan

Figures are numbered in **work order** — the sequence a reader performs — not in
the order things happened to be observed. Each one is the evidence that a step
worked.

| # | File | Section | What it shows | Where from |
|---|---|---|---|---|
| 01 | `01-before-state.png` | How We Built It | VPC Lattice console with no service networks and no services — the starting line | AWS console |
| 02 | `02-terraform-layout.png` | How We Built It | The files that build the week, each with its job and line count | Rendered card |
| 03 | `03-hcp-workspace-vars.png` | How We Built It | HCP workspace variables and OIDC — no static keys | HCP |
| 04 | `04-hcp-plan.png` | How We Built It | The plan, read before applying | HCP |
| 05 | `05-hcp-applied.png` | How We Built It | Applied, with the resource count | HCP |
| 06 | `06-service-network.png` | How We Built It | The service network, its VPC association and the associated service | AWS console |
| 07 | `07-auth-policy-active.png` | How We Built It | The service's auth policy — the named role, the GET condition, and **state Active** | AWS console |
| 08 | `08-allowed-call.png` | How We Built It | A signed call from `orders-client` returning 200 | Rendered card |
| 09 | `09-refused-call.png` | Challenges | The **same function**, signed as `stranger`, refused 403 — same VPC, same subnet, same security group | Rendered card |
| 10 | `10-policy-inactive.png` | Challenges | The trap: the identical policy with auth type NONE, reporting **state Inactive**, and the call succeeding anyway | AWS console |
| 11 | `11-test-results.png` | Challenges | All six tests with pass/fail | Rendered card |
| 12 | `12-destroyed.png` | Cleanup | Nothing left: no service network, no service, no associations, no VPC | Rendered card |
| 13 | `13-cost.png` | Cost | The billed figure, by usage type | Rendered card — see note |

## The two that carry the week

**09** is the argument. The same Lambda, in the same subnet, behind the same
security group, gets a different answer purely because of which role signed the
request. Put next to **08** it shows the thing a security group cannot express.

**10** is the failure mode. A policy that is attached, visible in the console,
indistinguishable from figure 07 at a glance — and inert. The only difference
on screen is one word: `Inactive`.

## Rules carried forward

- Every console and HCP figure is a **real capture** of a real screen, redacted
  automatically at capture time.
- Terminal output is a **rendered card from a committed `.card` source**, so it
  can be regenerated and corrected. Never a screenshot of a GitHub page.
- `13-cost.png` cannot exist until roughly a day after teardown, and `12` until
  the destroy has run; the pre-destroy gate exempts both.
- Anything retired goes in `UNUSED.txt` with a reason, not deleted quietly.
- Cost is read **grouped by usage type**. Grouping by service only ever says
  "VPC Lattice" and hides which dimension actually cost anything — Week 22's
  signing charge is why that rule exists.
