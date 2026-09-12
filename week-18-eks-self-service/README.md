# Week 18 — EKS Cluster Self-Service

**The story:** a namespace is a label, not a boundary. It does not limit CPU, does not stop a pod reaching a pod in another namespace, and has no bearing at all on AWS permissions. Every team that believes otherwise finds out during an incident.

This week builds a cluster where a new tenant gets a namespace that actually *is* a boundary — a quota, a network policy, and an AWS identity scoped to exactly one bucket — and then proves it by trying to break it.

---

## The collision that shaped the build

AWS recommends **EKS Pod Identity** over IRSA for giving pods AWS permissions. AWS also offers **Fargate** so you never manage a node.

**Do both and nothing works.** The Pod Identity agent is a privileged DaemonSet; Fargate runs neither DaemonSets nor privileged pods. The failure is silent: the webhook still injects the environment variables, so the pod looks correctly configured and then times out fetching credentials from an agent that was never there. It reads as an IAM misconfiguration for as long as you let it.

AWS's own answer is to run both mechanisms side by side. So this cluster has two tenants, deliberately different:

| | `tenant-a` | `tenant-b` |
|---|---|---|
| Compute | EC2 managed node | Fargate |
| Identity | **Pod Identity** | **IRSA** |
| Why | AWS's recommendation | the only option on Fargate |

---

## What makes a namespace a boundary

Three objects, none of which a namespace gives you:

| Object | Without it |
|---|---|
| **ResourceQuota** | one tenant can request every core in the cluster |
| **NetworkPolicy** | every pod can reach every other pod, in any namespace |
| **Pod Identity / IRSA** | pods inherit whatever the node role has |

---

## Proving it, rather than asserting it

```bash
BUCKET_A=... BUCKET_B=... ./scripts/prove_isolation.sh
```

Four checks. The two that matter are the ones expected to **fail**:

1. `tenant-a` → its own bucket — must succeed
2. `tenant-a` → `tenant-b`'s bucket — **must be denied**
3. `tenant-b` → its own bucket — must succeed
4. `tenant-b` → `tenant-a`'s bucket — **must be denied**

Run 1 and 3 alone and you have shown that permissions work. Only 2 and 4 show that they stop anything.

---

## Cost — read this before deploying

Prices as of September 2026 — verify at [aws.amazon.com/eks/pricing](https://aws.amazon.com/eks/pricing/).

| Item | Rate | Note |
|---|---|---|
| EKS control plane | **$0.10/hr** | from creation. **No free tier** |
| NAT gateway | **$0.045/hr** | from creation |
| t3.small node | ~$0.0208/hr | one, fixed |
| Fargate | $0.0405/vCPU-hr + $0.00444/GB-hr | per second, 1-min minimum |
| **Running total** | **~$0.17/hr ≈ $4/day** | whether or not a pod runs |

**This is the opposite shape to most of this series.** Weeks 11, 12 and 16 cost $0 on day one and began billing later, invisibly. EKS bills from the moment the cluster exists, visibly. That is easier to manage — provided teardown is part of the plan rather than an afterthought.

**Extended support is $0.60/hr**, six times standard, if the cluster falls off a supported Kubernetes version. Staying current is a cost decision.

---

## Cleanup

```bash
# destroy via HCP, then:
./scripts/cleanup.sh
```

The script checks clusters, NAT gateways, elastic IPs, VPCs, instances, roles, **OIDC providers**, buckets and log groups by name — then does a tag search on `Week=18` for anything the name checks missed.

OIDC providers are on that list deliberately: IRSA creates one per cluster, they are invisible in the EKS console, they survive a careless teardown, and IAM caps you at 100 per account.

---

## Security patterns

- **Two identity mechanisms, chosen by where the pod runs** — not by preference
- **Each tenant role reaches one bucket** — `s3:ListBucket` on the bucket, `GetObject`/`PutObject` on its contents, nothing else
- **IRSA trust policy pins both `:sub` and `:aud`** — without `:sub` any service account in the cluster can assume the role, and neither omission is visible until someone tries
- **NetworkPolicy denies cross-namespace ingress** — Kubernetes defaults to allowing it
- **Control plane audit logging on** — a denied cross-tenant call is only visible there
- **Cluster access via EKS access entries**, not a hand-edited `aws-auth` ConfigMap
