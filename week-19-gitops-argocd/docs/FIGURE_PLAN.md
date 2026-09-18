# Week 19 — figure plan, written BEFORE anything is captured

This file exists because of Week 18. That week captured ten screenshots and
then went looking for somewhere to put them, and the search is what broke the
post: a `kubectl` listing of live namespaces landed under "Step 1 — Decide what
the tenant boundary is made of", which is a step that runs *before* the cluster
exists. Jay found it after publishing. The same class of error was fixed three
separate times, and Week 17 turned out to have shipped it too.

The root cause was never carelessness about any single image. It was that the
post is organised by **topic** and the captures are numbered by **time**, and
nothing reconciled the two orderings. A screenshot has a topically perfect home
and a temporally impossible one, and topic wins when you are placing an image
you already have.

So the ordering is decided here, first, in narrative order. Capture fills these
slots. Capture order then equals narrative order by construction and there is
nothing left to reconcile.

## Rules this plan obeys

1. **Nothing above the deploy step may be a screenshot of live state.** Steps
   before the deploy produce Terraform code and decisions, not infrastructure.
   Anything above it is code blocks and prose only. This is enforced in CI by
   `scripts/check_figure_order.py` in the blog repo — it fails the build, so a
   violation cannot reach a reader even if this file is ignored.
2. **Numbers are assigned here and never reused.** If a capture turns out not to
   be worth publishing, its number is retired to `UNUSED.txt` with a reason, not
   recycled — recycling is how a number stops meaning "when this happened".
3. **A genuine pre-deploy prerequisite is allowed but must be declared** with
   `<figure class="screenshot" data-prereq>`, which is visible in the diff.
   Week 19 has one candidate: the Identity Center instance, which exists before
   any Terraform runs.

## The slots

| # | Filename | Section | What it must show | Exists only after |
|---|----------|---------|-------------------|-------------------|
| 01 | `01-identity-center-instance.png` | Step 1 (`data-prereq`) | The Identity Center instance and identity store the capability will authenticate against | already exists — precedes all Terraform |
| 02 | `02-hcp-run-applied.png` | **Step 4 — Deploy it** | The HCP Terraform run list for `week-19-dev`, applied, with the resource count | the apply |
| 03 | `03-eks-capability-argocd.png` | Step 4 | The EKS console Capabilities tab showing the Argo CD capability ACTIVE, with its server URL | the apply |
| 04 | `04-selfmanaged-pods.png` | Step 5 | `kubectl get pods -n argocd-self` — the five upstream Argo CD pods on the node | the Helm release |
| 05 | `05-argocd-ui-managed.png` | Step 5 | The managed Argo CD UI reached via its AWS URL, authenticated through Identity Center | capability + IdC assignment |
| 06 | `06-app-of-apps-synced.png` | Step 6 | Both Argo CD instances showing the same app-of-apps Synced / Healthy | first sync |
| 07 | `07-drift-reverted.png` | Verifying | A live `kubectl edit` change and Argo CD reverting it — self-heal working | drift test run 1 |
| 08 | `08-drift-not-reverted.png` | **Challenges** | The drift Argo CD does **not** revert, side by side with the drift it does | drift test run 2 |
| 09 | `09-capability-limits.png` | Challenges | Whatever the managed capability refuses that upstream allows (sync timeout, notifications, CMP) | attempted config |
| 10 | `10-cost-explorer.png` | Cost | Cost Explorer for the run window, by usage type | ~24h after teardown |

## Order check

Slots 02-10 are all below the deploy step. Slot 01 is above it and is the
declared prerequisite. Numbers ascend through the narrative. Running
`python scripts/check_figure_order.py week-19` against the finished post must
return `[ ok ]`, and `check_week_complete.py` must report every capture either
referenced or listed in `UNUSED.txt`.

## If the build deviates from this plan

Change this file first, then capture. A plan edited after the fact to match
what was captured is not a plan — it is a description, and it prevents nothing.
