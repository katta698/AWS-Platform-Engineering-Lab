# Week 26 — Tenant Isolation on DynamoDB, and the Cache That Removes It

**What you build:** one pooled DynamoDB table shared by two tenants, isolation
enforced by a `dynamodb:LeadingKeys` condition, and a DAX cluster in front of
it — then ten calls that show which of those controls survive the cache.

| | |
|---|---|
| **Cost** | ~$0.12/hour while the DAX cluster exists (3 × `dax.t3.small`); everything else is a few cents |
| **Provisioning** | Terraform ≥ 1.10, HCP Terraform workspace `week-26-dev` |
| **Region** | us-east-1 — a DAX cluster can only read tables in its own Region |

> **Status:** built; not yet deployed or validated. The Validation section
> below states what each case *should* do; the measured results go in the
> article once the lab has run.

The finding is not a misconfiguration. All three behaviours this lab
reproduces are documented by AWS, and all three read as safe:

- **DAX does not enforce DynamoDB's fine-grained access control.** AWS: *"users
  inherit the permissions of the DAX cluster's IAM policy when they access
  that cluster... No other permissions are recognized."* A cache added for
  latency is therefore a change to the authorisation boundary.
- **`ForAllValues:` passes when the condition key is absent.** `Scan` carries
  no partition key, so a `LeadingKeys` condition does not constrain it unless
  a `Null` companion is added.
- **`dynamodb:Attributes` is evaluated on the request, not the response.** Omit
  the `ProjectionExpression` and every attribute comes back regardless.

## 1. Prerequisites

| Requirement | Why | How to check |
|---|---|---|
| Terraform ≥ 1.10 | `cloud {}` block and the AWS provider v6 | `terraform version` |
| HCP Terraform login, org `Katta` | state and remote runs | `terraform login` |
| AWS credentials with DynamoDB, DAX, IAM, Lambda and VPC rights | the apply creates all five | `aws sts get-caller-identity` |
| Python 3.9+ with pip | builds the Lambda package | `python --version` |
| AWS CLI v2 | the teardown check reads the API directly | `aws --version` |

The workspace must be **CLI-driven, not VCS-connected**. The Lambda package is
built locally and uploaded with the configuration; a VCS run would only have
what is committed, and `build/` is not.

## 2. Source files

| Path | Its job |
|---|---|
| `terraform/environments/dev/main.tf` | VPC, gateway endpoint, table, DAX cluster and service role |
| `terraform/modules/tenant/main.tf` | one principal: Lambda, role, and the policy that is supposed to isolate it |
| `src/tenant_api/handler.py` | identical code for every tenant; takes the path as an argument |
| `scripts/build_package.sh` | installs `amazon-dax-client`, which is not in the Lambda runtime |
| `scripts/seed.py` | writes items for both tenants, each with a `secret_note` |
| `scripts/prove_isolation.py` | the ten cases, with expectations declared up front |
| `scripts/cleanup.sh` | destroy, then verify against the API |

Three principals are created from one module:

| Label | Scoped to | Guards | What it is for |
|---|---|---|---|
| `alpha` | `tenant-alpha` | `Null` + `Select` | the policy AWS documents |
| `beta` | `tenant-beta` | `Null` + `Select` | a second tenant to cross into |
| `audit` | `tenant-alpha` | none, and `Scan` added | the policy you get by writing the obvious thing and testing it with `GetItem` |

## 3. Deploy

```bash
./scripts/deploy.sh
```

Builds the package, applies, and seeds both tenants. Expect **10–12 minutes**,
nearly all of it the DAX cluster: nodes are provisioned one at a time and the
resource does not return until the cluster is available.

From the moment the cluster exists it bills whether or not anything reads from
it.

## 4. Run it

```bash
python scripts/prove_isolation.py --json results.json
```

Ten calls across three principals and two paths. Each case declares what it
expects before it runs, and the script exits non-zero if any case disagrees —
three of them expect to be *allowed* something they should not be, and a script
that only printed what happened would read the same whether the finding
reproduced or quietly stopped reproducing.

## 5. Validation

| Test | Expected |
|---|---|
| alpha reads its own item, direct | allowed — the baseline |
| alpha queries its own partition, direct | allowed |
| alpha reads beta's item, direct | **denied** — `LeadingKeys` refuses it |
| alpha queries beta's partition, direct | **denied** |
| alpha reads beta's item **through DAX** | **allowed** — the same call, cached |
| alpha queries beta's partition **through DAX** | **allowed** |
| alpha runs `Scan`, direct | denied — the guarded policy grants no `Scan` |
| audit runs `Scan`, direct | **allowed, returns both tenants** — vacuous condition |
| alpha reads with no projection | denied — `Select` pinned to `SPECIFIC_ATTRIBUTES` |
| audit reads with no projection | **allowed, returns `secret_note`** — attribute restrictions are on the request |

The four bold rows are the week. `secret_note` is in no policy's allowed
attribute list, so its presence in a response is the finding showing itself
rather than a claim about what a policy says.

## 6. Cleanup

```bash
./scripts/cleanup.sh
```

Destroys the stack and then checks the DAX cluster, the table and the Lambda
functions against the API — a destroy reports what Terraform removed, not what
is left in the account. Exits non-zero if anything survives.

## Cost

| Line | Rate (us-east-1, checked 2026-11-06) |
|---|---|
| DAX, `dax.t3.small` | ~$0.04 per node-hour; three nodes ≈ **$0.12/hour**, ~$2.88/day |
| DynamoDB on-demand writes | $0.625 per million |
| DynamoDB on-demand reads | $0.125 per million |
| Storage | $0.25 per GB-month |
| VPC gateway endpoint | free — deliberately chosen over NAT at $0.045/hour |

DAX is effectively the whole bill and it meters by the hour whether idle or
not. The lab's own request volume is a few hundred calls, which rounds to
nothing. Measured total goes here once the lab has run.

## Troubleshooting

To be filled from the build. Anything written here before the lab has run
would be a guess.

## References

- [DAX access control](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DAX.access-control.html) — the "can subvert those policies" warning
- [DAX cluster components](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DAX.concepts.cluster.html) — subnet groups, port 8111, three nodes for fault tolerance
- [Using IAM policy conditions for fine-grained access control](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/specifying-conditions.html) — `LeadingKeys`, the `Null` companion, and attributes on the request
- [Giving Lambda functions access to resources in a VPC](https://docs.aws.amazon.com/lambda/latest/dg/foundation-networking.html) — Hyperplane ENIs and the Lambda-managed VPC
