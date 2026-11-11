# Week 27 — What a Cache Actually Costs

**What you build:** one ElastiCache Serverless cache for Valkey, and the same
number of requests issued against three value sizes — then the bill for each.

| | |
|---|---|
| **Cost** | ~$0.08 estimated; $0.0084/hour storage floor plus $0.0023 per million ECPUs |
| **Provisioning** | Terraform ≥ 1.10, HCP Terraform workspace `week-27-dev` |
| **Region** | us-east-1 — a serverless cache is reachable only from its own VPC |

> **Status:** built; not yet deployed or validated.

Cache cost is not request count. AWS bills ElastiCache Serverless in ECPUs,
and an ECPU is *the higher of* two dimensions:

- **bytes moved** — one ECPU per KB read or written
- **vCPU time** — commands that work harder consume more

> *"If your command takes additional vCPU time and transfers more data than
> the baseline of 1 ECPU, then ElastiCache calculates the ECPUs required
> based on the higher of the two dimensions."*

So the dashboard everyone watches — requests per second — reads none of what
drives the bill.

## 1. Prerequisites

| Requirement | Why | How to check |
|---|---|---|
| Terraform ≥ 1.10 | `cloud {}` block, AWS provider v6 | `terraform version` |
| HCP Terraform workspace, CLI-driven | the package is built locally and uploaded | `terraform init` |
| AWS permissions for ElastiCache, Lambda, VPC, IAM | the apply creates all four | `aws sts get-caller-identity` |
| Python 3.11+ with pip | builds the package; `valkey-py` is not in the runtime | `python --version` |
| AWS CLI v2 | teardown is verified against the API | `aws --version` |

## 2. Source files

| Path | Its job |
|---|---|
| `terraform/environments/dev/main.tf` | VPC, security groups, serverless cache, client function |
| `src/cache_client/handler.py` | issues N reads at a given value size |
| `scripts/build_package.sh` | installs `valkey-py` into the package |
| `scripts/run_experiment.py` | the three sizes, and the cost of each |
| `scripts/cleanup.sh` | figure gate, destroy, then verify against the API |
| `docs/FIGURE_PLAN.md` | what must be captured before teardown |

## 3. Deploy

```bash
./scripts/deploy.sh
```

Builds the package and applies. A serverless cache takes a few minutes to
become available.

## 4. Run it

```bash
python scripts/run_experiment.py --json results.json
```

200,000 reads at 1 KB, 10 KB and 100 KB. Identical request counts.

## 5. Validation

| Test | Expected |
|---|---|
| 200k reads at 1 KB | ~200k ECPUs |
| 200k reads at 10 KB | ~2M ECPUs — same requests, ten times the ECPUs |
| 200k reads at 100 KB | ~20M ECPUs — same requests, a hundred times |
| CloudWatch `ElastiCacheProcessingUnits` | three plateaus at one request rate |
| `BytesUsedForCache` | below the 100 MB minimum billed storage |

Measured results go in the article once the lab has run.

## 6. Cleanup

```bash
./scripts/cleanup.sh
```

Refuses while a figure declared in `docs/FIGURE_PLAN.md` is uncaptured, then
destroys and checks the cache and functions against the API.

## Cost

| Line | Rate (us-east-1, checked 2026-11-10) |
|---|---|
| Storage | $0.084/GB-hour, minimum **100 MB** billed |
| ECPUs | $0.0023 per million |
| VPC | free — no NAT, the client sits with the cache |

The 100 MB floor is ~$0.0084/hour, about $6.13/month. AWS states there is
"no minimum fee" and also a 100 MB minimum billed storage; both are true.

Measured total goes here once the lab has run.

## Troubleshooting

To be filled from the build.

## References

- [ElastiCache pricing](https://aws.amazon.com/elasticache/pricing/) — ECPUs, and the minimum billed storage per engine
- [ElastiCache Serverless](https://docs.aws.amazon.com/AmazonElastiCache/latest/dg/serverless-getting-started.html) — TLS is always on and cannot be disabled
- [Terraform — `aws_elasticache_serverless_cache`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/elasticache_serverless_cache)
- [valkey-py](https://pypi.org/project/valkey/) — the client, not present in the Lambda runtime
