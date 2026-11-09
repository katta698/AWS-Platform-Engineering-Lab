# Week 26 — Tenant Isolation on DynamoDB, and the Cache That Removes It

**What you build:** one pooled DynamoDB table shared by two tenants, isolation
enforced by a `dynamodb:LeadingKeys` condition, and a DAX cluster in front of
it — then ten calls that show which of those controls survive the cache.

| | |
|---|---|
| **Cost** | **$0.1202 measured** for one cycle (DAX $0.1200, DynamoDB $0.0002); ~$0.12/hour for as long as the cluster exists |
| **Provisioning** | Terraform ≥ 1.10, HCP Terraform workspace `week-26-dev` |
| **Region** | us-east-1 — a DAX cluster can only read tables in its own Region |

> **Status:** built, validated and destroyed on 2026-11-08. All ten cases
> behaved as predicted. The DAX cluster, the table, the three functions and
> the VPC were confirmed gone against the API, not against the destroy
> output.

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
| `terraform/environments/dev/main.tf` | everything: VPC, gateway endpoint, table, DAX cluster and service role, and the three principals |
| `src/tenant_api/handler.py` | identical code for every tenant; takes the path as an argument |
| `scripts/build_package.sh` | installs `amazon-dax-client`, which is not in the Lambda runtime |
| `scripts/seed.py` | writes items for both tenants, each with a `secret_note` |
| `scripts/prove_isolation.py` | the ten cases, with expectations declared up front |
| `scripts/cleanup.sh` | destroy, then verify against the API |

Three principals are created with one `for_each`. They were a child module
until it met HCP's upload boundary -- a remote run uploads the root module
directory and nothing above it, so `../../modules` did not exist at plan
time:

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

**Measured 2026-11-08: 10/10 cases matched.** The two that matter most, side
by side -- `alpha` asking for `tenant-beta`'s item returned
`AccessDeniedException` on the direct path and returned tenant-beta's data
through DAX. Same call, same role, same table. `vacuous-scan` returned
`tenants=tenant-alpha,tenant-beta`, and `attributes-on-request` returned
`LEAKED=secret_note`. Figure `02-isolation-truth-table.png`.

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
nothing.

The cluster existed for roughly 50 minutes on 2026-11-08. DAX bills per
node-hour **or partial hour**, so that is three node-hours: **$0.12**. A
deploy-test-destroy cycle cannot cost less than that however fast it runs.

**Measured 2026-11-09, for the 8 November run: $0.1202.** Cost Explorer
reports $0.1200 against DynamoDB Accelerator and $0.0002 against DynamoDB.
The estimate and the bill agree, which is worth recording only because they
often do not — a rate card gives the price of a thing, not how many of them
a lab turns out to use.

## Troubleshooting

**A Local Zone sorted first, and DAX refused the subnet group.**
`SubnetNotAllowedFault: Subnet ... is not in a supported availability zone`.
This account has a Local Zone enabled (`us-east-1-dfw-1a`, Dallas), and
`aws_availability_zones` returns names sorted alphabetically -- where
`us-east-1-dfw-1a` sorts *before* `us-east-1a`, because `-` precedes `a`. So
taking the first three names put a Local Zone at index 0.
*Fix:* filter the data source to `zone-type = availability-zone`, which
excludes Local Zones and Wavelength Zones. Do not hardcode AZ names; the
filter says what was meant.

**A child module that does not exist during a remote run.**
`Unable to evaluate directory symlink: lstat ../../modules: no such file or
directory`. An HCP remote run uploads the root module directory and nothing
above it, so `../../modules` is simply absent at plan time. The same applies
to anything an `archive_file` reads from a parent directory.
*Fix:* express the three principals with `for_each` in the root module, and
build the Lambda zip into the root module directory. Switching the workspace
to local execution also works and produces no HCP run page, which this series
needs every week.

**Terraform replaced all three functions on every apply.**
The package hashed differently each build. `pip` emits console-script
wrappers into `bin/`, which on Windows are `.exe` files that embed a path --
unreproducible, and useless in a Linux runtime. `RECORD` then stores a hash
of each one.
*Fix:* delete `bin/` and the `*.dist-info/RECORD` files before zipping, write
the zip with fixed member timestamps, and strip the `__pycache__` the import
check leaves behind. The package went from 4.9MB to 652KB as a side effect.

**The teardown check could only ever pass.**
`cleanup.sh` looked for a DAX cluster named `week26-tenant-isolation`, but
DAX caps `cluster_name` at 20 characters so the cluster is
`week26-isolation`. The check queried a name that never existed and reported
"gone" regardless -- on the one resource billing by the hour.
*Fix:* query the real name. The failure was proved first by running the old
query against a cluster that was running at the time and watching it report
not-found.

## References

- [DAX access control](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DAX.access-control.html) — the "can subvert those policies" warning
- [DAX cluster components](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/DAX.concepts.cluster.html) — subnet groups, port 8111, three nodes for fault tolerance
- [Using IAM policy conditions for fine-grained access control](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/specifying-conditions.html) — `LeadingKeys`, the `Null` companion, and attributes on the request
- [Giving Lambda functions access to resources in a VPC](https://docs.aws.amazon.com/lambda/latest/dg/foundation-networking.html) — Hyperplane ENIs and the Lambda-managed VPC
