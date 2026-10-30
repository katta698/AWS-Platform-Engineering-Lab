# Week 25 figure plan

Written **before deploying**, deliberately. Figures 01–04 can only be captured
while the stack exists, and 01 only before it exists at all. A plan written
after the build is a list of what happened to be captured.

Target is **4–7 figures** in the published post (Master Standard §4). Nine
slots are planned here; the weakest get cut at write-up rather than discovered
missing.

| # | File | Section | What it shows | Source | When |
|---|------|---------|---------------|--------|------|
| 01 | `01-before-state.png` | Implementation | Both regions side by side: us-east-1 with 13 functions, us-east-2 with 0 — the empty region that is the experiment's fence | **Real terminal** | **before apply — DONE** |
| 02 | `02-hcp-workspace-vars.png` | Implementation | HCP workspace variables and OIDC — no static keys | HCP | **DONE 2026-10-29** |
| 03 | `03-hcp-applied.png` | Implementation | Applied, with the resource count | HCP | **DONE 2026-10-29** |
| 04 | `04-three-functions.png` | Implementation | Three functions in `us-east-2`, none with reserved concurrency | AWS console | **DONE 2026-10-29** |
| 05 | `05-baseline-healthy.png` | Validation | checkout returning 200 at a steady rate before any load | Real terminal | run 1, baseline |
| 06 | `06-pool-filling.png` | Validation | **The week.** CloudWatch: neighbours' concurrency climbing, checkout's throttles starting only once the pool is full | AWS console | run 1 |
| 07 | `07-checkout-starved.png` | Validation | The recorder's own output — checkout's success rate collapsing while nothing about checkout changed | Real terminal | run 1 |
| 08 | `08-protected-holds.png` | Validation | Same load, checkout reserved, success rate holding | Real terminal | run 2 |
| 09 | `09-cost.png` | Security and Cost | Measured cost by usage type | Real terminal | after the bill |
| 10 | `10-destroyed.png` | Cleanup | Nothing left in `us-east-2`, queried against AWS | Real terminal | after destroy |

## Changed from the original plan

Figure 01 was planned as an AWS console screenshot of the empty region. It is a
**terminal capture** instead, and the change is an improvement rather than a
compromise: the console shows one region's empty state, while the terminal
shows *both* regions side by side with their function counts and quotas, which
is the actual comparison the fence rests on. It also needs no browser session,
so it could be taken at the moment it was needed rather than when a signed-in
Chrome happened to be running.

## The two that carry the week

**06** is the mechanism. Three lines on one chart: two neighbours climbing, the
pool filling, and checkout's throttles beginning *only* at the moment it is
full. A reader should be able to see the causation without the caption.

**07 beside 08** is the proof. Identical load, identical code, identical
region. The only difference is one Terraform attribute, and the success rate
goes from collapsed to intact.

## Rules being followed, so they are not rediscovered later

- **Terminal figures are real captures** (`capture_terminal.py`), never typeset
  cards. The commands live in `docs/blog/terminal/*.sh` and are committed, so
  every figure can be regenerated.
- **Console and HCP figures are real screenshots** of the real surface.
- **Figure 01 must be taken before `terraform apply`.** An empty-region
  screenshot cannot be recreated once three functions exist, and redeploying to
  fake it would be staging evidence.
- **Redaction is mine, not Jay's** — account id, signed-in identity, any ARN
  carrying the account number.
- Renders are copied into `docs/blog/screenshots/`. `figures/` is gitignored,
  and a post pointing there 404s for every reader.

## Deliberately not captured

A screenshot of the Terraform source. The Master Standard forbids repository
trees with line counts and full source listings in the article; the compact
directory tree in Implementation and links to GitHub cover it.
