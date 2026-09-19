# Week 19 — GitOps on EKS: who should run Argo CD?

**Status: complete.** Built and destroyed 18 September 2026, cluster `week19-gitops`
alive 5h19m (13:02–18:21 UTC). `cleanup.sh` clean on all eleven checks.
Published: https://jayanthkatta.com/blog/week-19-gitops-argocd/

Every Argo CD tutorial shows the same thing: `helm install`, get the admin
password out of a Kubernetes secret, port-forward the UI. That was the only
option for years.

It is not the only option now. AWS shipped **Argo CD as an EKS Capability**
(GA 30 November 2025), where the Argo CD controllers run in AWS-managed
infrastructure *outside* your cluster and authenticate through IAM Identity
Center. So the interesting question is no longer *how do I install Argo CD*.
It is **should I run it at all, or let AWS?**

This week built both, on one cluster, reading the same Git repository and
deploying the same application — so the only variable is who operates Argo CD.

## What this builds

```
week19-gitops (EKS 1.36, one t3.medium)
├── argocd        EKS Capability for Argo CD   ← AWS runs the controllers
└── argocd-self   Helm chart 10.9.1            ← you run the controllers
        │
        └── both deploy → gitops-demo/podinfo, from this repo
```

## What it found

**The two Argo CDs cannot both own the CRDs.** The first apply built everything
and failed on the Helm release: `applications.argoproj.io in namespace "" exists
and cannot be imported`. The capability installs Argo CD's CRDs, and CRDs are
**cluster-scoped** — separate namespaces isolate Deployments and config and
isolate nothing about shared type definitions. Helm's refusal is correct:
adopting would mean a later `uninstall` deletes a CRD it does not own, taking
every Application cluster-wide with it. Fixed with `crds.install = false`.

**The capability really does run outside the cluster.** `kubectl get pods -n
argocd` returns *No resources found*; `argocd-self` lists **seven** pods.

**It ships unable to deploy anywhere but its own namespace.** The auto-created
access entry grants `AmazonEKSArgoCDClusterPolicy` (cluster) and
`AmazonEKSArgoCDPolicy` (**namespace=argocd only**). The Application sits at
Sync **Unknown** / Health **Healthy** — *could not look*, not *looks wrong*.

**AWS's documented RBAC fix binds to a group that does not exist.** The docs say
bind a ClusterRole to `eks-access-entry:<principal-arn>`; the auto-created entry
has **`"groups": []`**, so that binding is inert until you add a group with
`aws eks update-access-entry --kubernetes-groups`.

**Two controllers on one namespace: the last writer owns it.** The tracking
annotation became `argocd_podinfo:...` (the capability's format). It reported
everything Synced; the Helm install reported everything OutOfSync, permanently.

**Cost was not the deciding factor, which was the surprise.** The capability is
$0.03 per hour plus $0.0015 per Application-hour. Upstream Argo CD is free
software that needs a node one size larger to hold its pods — t3.small to
t3.medium is $0.0208/hour. Close enough that "managed costs more" does not
survive contact with the rate card; the feature list decides instead.

**The managed capability genuinely does less.** Per AWS's own comparison page:
no Config Management Plugins, no Notifications controller, no SSO provider
other than Identity Center, no UI extensions, most configuration ConfigMaps
inaccessible, and **the sync timeout is fixed at 120 seconds**.

**Identity Center is a hard prerequisite**, not a recommendation — "local users
are not supported". There is no admin password in a Kubernetes secret, which is
how every upstream tutorial begins.

**One field differs between the two Application manifests**, and it is not
cosmetic. Upstream registers its own cluster as `https://kubernetes.default.svc`.
The capability accepts only EKS cluster ARNs and does not auto-register the
local cluster, because it runs outside the cluster — where "this cluster" is an
AWS resource, not a network address.

## The thing deliberately broken — and what happened

GitOps' headline claim is that Git is the source of truth and the cluster
self-heals back to it. `scripts/prove_drift.sh` went looking for the edge of
that claim rather than demonstrating it. **Final run: 11 passed, 0 failed,
0 BROKEN.**

| Drift | Result |
|---|---|
| A field Git specifies (replicas) | **Reverted**, inside 3 seconds |
| A field Git never mentions (annotation) | **Survives** — nothing to converge it to |
| A resource created by hand | **Never pruned** — it was never tracked |
| A resource Git declares, deleted | **Recreated**, with a new uid |

Two cases first reported `BROKEN`, which was the honest answer and not a
finding: Argo CD was faster than the observation. Both now measure a fact that
cannot be undone — `metadata.generation` for the mutation (it went 5 → 7, two
spec writes inside three seconds) and `metadata.uid` for the delete.

The script reports three outcomes, not two. **A check whose precondition did
not hold is `BROKEN` — never a pass.** Week 18 published a test that scored two
of four checks green against pods that never started, because the checks only
searched for a failure string and work that never happens produces no string.
Every check here proves its drift actually landed before it reports on what
happened next.

## Cost

| Item | Rate |
|---|---|
| EKS control plane | $0.10 / hr, from creation, no free tier |
| NAT gateway | $0.045 / hr |
| t3.medium node | ~$0.0416 / hr — twice Week 18's t3.small, because Argo CD has to fit |
| Argo CD capability | $0.03 / hr + $0.0015 per Application-hour |

About **$0.22/hr, ~$5.20/day**, whether or not anything syncs.

**Billed: $1.21** for the 5h19m run (Cost Explorer, 19 September). Control
plane $0.51, NAT $0.30, node $0.21, **capability $0.15** ($0.144 in
capability-hours plus $0.007 in Application-hours, itemised separately), and
$0.04 of Elastic IP, EBS and regional data transfer. The rate line predicts
$1.17 — 3% under, and the gap is entirely the three items a rate table never
lists.

## Layout

```
docs/FIGURE_PLAN.md    screenshot slots, written BEFORE any capture
gitops/                what Argo CD reads — workloads and Application CRs
scripts/prove_drift.sh the drift experiment
scripts/cleanup.sh     teardown verification, including the capability
terraform/
  modules/platform_cluster      VPC, EKS, node, OIDC, access entries
  modules/argocd_managed        aws_eks_capability, type ARGOCD
  modules/argocd_selfmanaged    helm_release, chart pinned to 10.9.1
  environments/dev              both paths on one cluster
```

## Teardown

```bash
# destroy via HCP, then verify nothing survived
./scripts/cleanup.sh
```

An EKS Capability is an AWS resource with its own billing line and is invisible
to `kubectl`. Its IAM role outlives it at no cost, which is exactly how orphans
accumulate.

## Sources

- [Comparing EKS Capability for Argo CD to self-managed Argo CD](https://docs.aws.amazon.com/eks/latest/userguide/argocd-comparison.html)
- [Amazon EKS capability IAM role](https://docs.aws.amazon.com/eks/latest/userguide/capability-role.html)
- [Amazon EKS pricing](https://aws.amazon.com/eks/pricing/)
- [Argo CD releases](https://endoflife.date/argo-cd)
