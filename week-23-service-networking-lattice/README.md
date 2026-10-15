# Week 23 — Service Networking with VPC Lattice

**The goal, in one sentence:** make one service callable only by a named
identity — and prove the wrong identity is genuinely refused.

The demonstration is deliberately narrow. Two Lambda functions sit in the
**same VPC, the same subnet, behind the same security group**. One may call the
service; the other may not. The only difference between them is which IAM role
signs the request.

A security group cannot tell those two apart. It knows addresses, not
identities.

| Control | What it can say | What it cannot say |
|---|---|---|
| Security group | "this CIDR may reach port 80" | "only the orders service may call rates" |
| VPC Lattice auth policy | "role `orders-client` may GET `/rates`" | nothing about the *contents* of the call |

> **Not App Mesh.** App Mesh shut down on 30 September 2026 and cannot be
> created. VPC Lattice is what AWS points to in its place. That is the only
> reason App Mesh is mentioned anywhere in this week.

---

## Before you start

| | |
|---|---|
| Terraform | >= 1.10 |
| AWS provider | >= 6.68 |
| HCP Terraform | A workspace you can create, with OIDC to AWS |
| Docker | Not needed |
| Cost | Under $0.10 for a few hours — see Cost |

```bash
# Nothing should exist yet.
aws vpc-lattice list-service-networks --query 'length(items)' --output text
aws vpc-lattice list-services         --query 'length(items)' --output text
```

---

## The order

Eight steps. Each ends with a check, because a step you cannot verify is a step
you cannot debug later.

### 1. Look at the starting state — *console*

**VPC Lattice → Service networks**, and **Services**. Both empty.

→ *Figure 01.* **Check:** both lists return 0.

### 2. Write the Terraform — *laptop*

```
terraform/
  environments/dev/      # backend, providers, the module call
  modules/lattice/
    network.tf           # VPC, subnets, the shared security group
    lattice.tf           # service network, service, listener, both auth policies
    compute.tf           # the two Lambdas and three roles
lambda/backend/          # the protected service
lambda/client/           # the caller, signs as either identity
```

**The detail that costs you an afternoon.** The SigV4 service name for calling
*through* Lattice is `vpc-lattice-svcs`. `vpc-lattice` is the control plane —
the API you use to create service networks. Sign with the wrong one and you get
a 403 that is indistinguishable from a policy denial.

→ *Figure 02.* **Check:** `terraform fmt` and `terraform validate` both clean.

### 3. Create the HCP workspace — *HCP*

Workspace `week-23-dev`, working directory `terraform/environments/dev`, AWS
credentials via **OIDC** (`TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN`).

→ *Figure 03.* **Check:** no static access keys anywhere.

### 4. Plan, and read it — *HCP*

You are looking for a resource you did not intend, and for `auth_type` being
set on **both** the service network and the service.

→ *Figure 04.* **Check:** the count matches what you meant to build.

### 5. Apply — *HCP*

→ *Figure 05.* **Check:** applied, and the outputs give you the service DNS.

### 6. Verify in the console — *console*

Code applying is not the same as a control being on.

- **Service network** — the VPC association and the associated service
- **The service's auth policy** — the named role, the GET condition, and
  **`state: Active`**

That last word is the one to look at. It is the difference between figure 07
and figure 10.

→ *Figures 06, 07.* **Check:** the console agrees with the code.

### 7. Run the tests — *laptop*

```bash
bash scripts/test_auth.sh
```

| # | Test | Expect |
|---|---|---|
| 1 | Unsigned request | 403 |
| 2 | Signed as `orders-client`, GET | **200** |
| 3 | Signed as `stranger`, GET | 403 |
| 4 | Signed as `orders-client`, POST | 403 |
| 5 | Policy attached, `auth_type = NONE` | 200, policy reads `Inactive` |
| 6 | `auth_type = AWS_IAM`, policy deleted | 403 — fails closed |

Order matters. Test 2 establishes that an allowed call works at all; a refusal
in test 3 proves nothing until test 2 has passed, because everything would be
refused if the plumbing were simply broken.

**What makes test 3 honest:** the `stranger` role is *granted*
`vpc-lattice-svcs:Invoke` in its own IAM policy. Without that, a 403 would only
prove the identity policy refused it. With it, the refusal can only have come
from the auth policy.

→ *Figures 08, 09, 10, 11.*

### 8. Destroy, then verify — *HCP + terminal*

```bash
python ../scripts/hcp_destroy.py week-23-dev    # blocks if figures are missing
bash scripts/cleanup.sh                         # verifies what destroy left
```

A VPC cannot be deleted while a service network association survives, so a
half-finished destroy leaves a VPC that looks orphaned and is not.

→ *Figure 12.* Cost comes a day later (*Figure 13*).

---

## What it builds

| What | Count | Its job |
|---|---|---|
| Service network + VPC association | 2 | The switchboard, and the consumer VPC attached to it. The association is free |
| Service + listener + target group + attachment | 4 | The thing being called |
| Service network ↔ service association | 1 | Puts the service on the switchboard |
| **Auth policies** | **2** | Layer one: org + source VPC. Layer two: named role + GET only |
| Lambdas (backend, client) | 2 | The protected service, and the caller |
| IAM roles + policies | 6 | `orders-client`, `stranger`, backend — and the grants that make the test honest |
| VPC, subnets, security group | 4 | One network, shared by both callers on purpose |
| Log groups | 2 | |

23 resources. Only the two auth policies are the point; the rest is what any
service behind any front door needs.

**No NAT gateway, no internet gateway, no load balancer.** The client reaches
the service through the VPC association, which costs nothing.

---

## Security

- **Two layers, both deny-by-default.** The service network policy sets the
  coarse boundary (this org, this VPC); the service policy sets the fine one
  (this role, this method). Both must allow.
- **The security group is deliberately permissive and shared** by both callers.
  If it were doing the authorisation, both would get the same answer. It is in
  the build to show what it *cannot* do.
- **No public endpoint.** The service DNS resolves only inside an associated
  VPC.
- **SigV4 signing**, so requests are authenticated rather than merely routed.
- **Least privilege**, with one deliberate exception: `stranger` is granted
  `Invoke` so that its refusal proves the right thing.
- **The honest limit:** Lattice authorises *who is calling*, not *what they
  send*. An allowed caller can still send something harmful. This replaces
  network-position trust, not input validation.

---

## Cost

Under $0.10 for a few hours.

| Dimension | Rate |
|---|---|
| Per service | $0.025/hr |
| Data processed | $0.025/GB |
| Requests | first 300,000/hr free, then $0.10/million |
| VPC association, service network endpoints | **free** |

One service is effectively the whole bill. Lambda invocations and data are
rounding errors, and the test suite is a few dozen requests against a free
allowance of 300,000.

**Resource gateways are deliberately not used.** They bill **$0.10/hr per
resource** — four times a service — and exist to reach things that are not
Lattice services (an RDS instance, an on-premises host). Worth knowing before
you switch one on to "just try it".

Read the bill **grouped by usage type**, not by service. Grouping by service
only ever says "VPC Lattice".

**Billed total:** filled in from the bill after teardown, not estimated here.

---

## What production does differently

- **Cross-account.** The service network is shared through RAM and consumers
  live in other accounts. The auth policy then earns its keep, because
  `aws:PrincipalOrgID` and `SourceVpcOwnerAccount` start doing real work. Here
  everything is one account, which keeps the week honest about what was
  actually tested.
- **HTTPS listeners** with ACM certificates rather than plain HTTP.
- **Access logs** to S3 or CloudWatch, which this build omits for cost.
- **Real workloads** behind the service instead of a Lambda returning a number.

---

## Teardown

Destroyed and verified — details once the week has run.
