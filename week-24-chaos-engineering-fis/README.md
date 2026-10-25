# Week 24 — Chaos Engineering with AWS FIS

**Reproducible lab guide.** The companion article explains the problem, the
architecture and the findings; this file is what you run.

> **Article:** https://jayanthkatta.com/blog/week-24-chaos-engineering-fis/

**What you build:** an ECS Fargate service behind an ALB, two CloudWatch alarms
with deliberately different evaluation windows, and three AWS FIS experiment
templates that inject the same fault under different guards — none, a fast
alarm, a slow alarm.

**What you learn:** whether a FIS stop condition can actually stop anything.

| | |
|---|---|
| **Difficulty** | Intermediate |
| **Time** | ~90 minutes including teardown |
| **Measured cost** | **$1.26** for the full run (see [Cost](#cost)) |
| **Region** | `us-east-1` |
| **Provisioning** | Terraform via HCP Terraform (Terraform Cloud) with OIDC |

---

## 1. Prerequisites

### Accounts and permissions

| Requirement | Detail |
|---|---|
| AWS account | Able to create ECS, ELB, IAM, CloudWatch and FIS resources |
| AWS CLI | v2, authenticated (`aws sts get-caller-identity` must succeed) |
| HCP Terraform account | A workspace with an AWS OIDC role — no static keys |
| Terraform | 1.15.x (this lab ran 1.15.8) |
| Python | 3.11+, for `summarise.py` |
| Bash | For the run scripts (Git Bash on Windows is fine) |

### AWS quotas that matter

| Quota | Default | Why it matters |
|---|---|---|
| Actions per FIS experiment template | **20** | The repeated-fault template uses 13 |
| FIS experiment duration | 12 hours | Not a constraint here |
| Active FIS experiments | 5 | Not a constraint here |

Check with:

```bash
aws service-quotas list-service-quotas --service-code fis --region us-east-1 \
  --query "Quotas[?contains(QuotaName,'per experiment template')].[QuotaName,Value]" \
  --output table
```

### Network assumption

The service runs in the **default VPC** with `assignPublicIp: ENABLED`, and the
ALB shares those subnets. This keeps the lab to 19 resources and no NAT gateway.

**Production delta:** put tasks in private subnets behind a NAT gateway or VPC
endpoints, and keep the ALB in public subnets. This also matters if you want to
extend the lab with `aws:network:disrupt-connectivity`, which targets *subnets* —
with a shared-subnet layout it would cut the load balancer as well as the tasks.

### No prerequisite labs

Week 24 is self-contained. The service module is adapted from Week 21's
blue/green ECS build, but nothing from that week needs to exist first.

---

## 2. Source files

| File | Purpose |
|---|---|
| [`terraform/environments/dev/main.tf`](terraform/environments/dev/main.tf) | HCP backend, OIDC provider, wires the two modules |
| [`terraform/modules/service/main.tf`](terraform/modules/service/main.tf) | ECS cluster, Fargate service, ALB, target group, **both alarms** |
| [`terraform/modules/chaos/main.tf`](terraform/modules/chaos/main.tf) | FIS role, log group, **three experiment templates** |
| [`scripts/run-experiment.sh`](scripts/run-experiment.sh) | Starts an experiment and records state every 2s through to recovery |
| [`scripts/summarise.py`](scripts/summarise.py) | Turns a recording into impact / alarm / damage numbers |
| [`docs/FINDINGS.md`](docs/FINDINGS.md) | The four findings, with the evidence for each |
| [`docs/blog/terminal/`](docs/blog/terminal/) | The exact command scripts behind the article's terminal figures |

### The two alarms — the whole experiment

Generated so they cannot differ in anything except evaluation window:

```hcl
metric_name         = "HealthyHostCount"   # NOT UnHealthyHostCount — see below
statistic           = "Minimum"            # NOT Average
threshold           = var.desired_count
comparison_operator = "LessThanThreshold"

# fast                      # typical
period              = 60    # period              = 300
datapoints_to_alarm = 1     # datapoints_to_alarm = 2
```

**Why `HealthyHostCount` and not `UnHealthyHostCount`:** when FIS stops an ECS
task, ECS *deregisters* it from the target group. A deregistered target is not
unhealthy, it is absent, so `UnHealthyHostCount` stays at `0` for the entire
fault. An alarm built on it can never fire. This was measured, not assumed —
see [Validation](#5-validation).

**Why `Minimum` and not `Average`:** over a 300-second window a one-minute dip
from 4 healthy to 2 averages to about 3.6 and never crosses a threshold of 4.

### Tag propagation — easy to get wrong

```hcl
enable_ecs_managed_tags = true
propagate_tags          = "SERVICE"
tags                    = merge(var.tags, { FISTarget = var.name })
```

FIS selects tasks by tag, and **a task does not inherit its service's tags**
unless `propagate_tags` says so. Without this the experiment targets nothing,
reports success, and the service stays up.

---

## 3. Deploy

```bash
cd terraform/environments/dev
terraform init
terraform plan      # expect: 19 to add, 0 to change, 0 to destroy
terraform apply
```

If you drive HCP through the API rather than the CLI, **pin the configuration
version**. A run created without one reuses the last version HCP ingested, which
may not be your latest push — it will report "no changes" while your fix never
ran. Use [`scripts/hcp_apply_pinned.py`](../scripts/hcp_apply_pinned.py), which
waits for the configuration version whose commit SHA matches `HEAD` and refuses
if it never arrives.

### Expected result

```
Apply complete! Resources: 19 added, 0 changed, 0 destroyed.
```

19 managed resources (25 state entries, 6 of which are data sources):

| Resource | Count |
|---|---|
| ECS cluster, service, task definition | 3 |
| ALB, listener, target group | 3 |
| Security groups | 2 |
| CloudWatch alarms | 2 |
| FIS experiment templates | 3 |
| IAM roles and policies | 4 |
| CloudWatch log groups | 2 |

### Validation checkpoint — deployment

Deployment succeeding is **not** the same as the lab working. Confirm the
service is actually serving before injecting anything:

```bash
aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --query 'TargetHealthDescriptions[].TargetHealth.State' --output text
# expect: healthy healthy healthy healthy

curl -s -o /dev/null -w '%{http_code}\n' "http://$ALB_DNS/"
# expect: 200
```

---

## 4. Run the experiments

```bash
bash scripts/run-experiment.sh recovery   # no stop condition — baseline
bash scripts/run-experiment.sh fast       # guarded by the 60s alarm
bash scripts/run-experiment.sh typical    # guarded by the 300s alarm
```

Each run writes a CSV to `results/` with one row every 2 seconds:

```
elapsed_s,phase,fis_state,healthy,unhealthy,alarm_fast,alarm_typical
```

### Two things the runner refuses to do

**It will not start against an alarm already in `ALARM`.** A tripped stop
condition halts the experiment at `t=0`; FIS reports `stopped` and the run looks
like an instant, heroic save. It measured the *previous* run. The typical alarm
stays tripped for about ten minutes after recovery, so back-to-back runs hit
this constantly.

**It does not stop watching when FIS does.** FIS reports `completed` when its
last action *returns*, not when the fault has played out. Measured: FIS reported
completed at 22:56:31; ECS started replacement tasks at 22:57:08 and the
originals did not reach `STOPPED` until 22:57:41 — 70 seconds later. The runner
keeps sampling through an `aftermath` phase until the service is whole for three
consecutive polls.

```bash
python scripts/summarise.py results/*.csv
```

---

## 5. Validation

### Did the fault actually land?

A FIS experiment reporting `completed` proves only that the API call returned.
Confirm tasks were really stopped:

```bash
aws ecs describe-tasks --cluster week24-chaos --tasks "$TASK_ARN" \
  --query 'tasks[0].{stopped:stoppedAt,reason:stoppedReason}'
# expect reason: "Task stopped by AWS FIS (Experiment ID: EXP...)"
```

And check how many targets FIS actually resolved — the console shows this as
**Resources targeted**:

```bash
aws fis get-experiment --id "$EXPERIMENT_ID" \
  --query 'experiment.{state:state.status,targets:targets}'
```

### Proving the metric problem

This is the finding the lab exists for. Run both metrics over a window in which
you know capacity dropped:

```bash
aws cloudwatch get-metric-statistics --namespace AWS/ApplicationELB \
  --metric-name UnHealthyHostCount --statistics Maximum --period 60 \
  --dimensions Name=TargetGroup,Value=$TG_SUFFIX Name=LoadBalancer,Value=$LB_SUFFIX \
  --start-time 2026-10-24T03:50:00Z --end-time 2026-10-24T04:05:00Z \
  --query 'sort_by(Datapoints,&Timestamp)[].[Timestamp,Maximum]' --output table
```

**Observed:** `UnHealthyHostCount` returned `0.0` for *every* one-minute
datapoint, while `HealthyHostCount` (Minimum) showed the dip from 4 to 2.

### Cleanup verification

See [`docs/blog/terminal/12-destroyed.sh`](docs/blog/terminal/12-destroyed.sh) —
the exact script behind the article's teardown figure.

---

## 6. Cleanup

```bash
cd terraform/environments/dev
terraform destroy
```

Or through HCP, which keeps teardown a traceable action rather than a console
click:

```bash
python ../scripts/hcp_destroy.py week-24-dev --message "Teardown: week 24"
```

### Verify — do not trust the destroy output

```bash
bash docs/blog/terminal/12-destroyed.sh
```

Queries ECS, ELB, FIS, CloudWatch, IAM and CloudWatch Logs for anything named
`week24`. All should return empty, and the HCP workspace resource count should
be `0`.

### Nothing is shared

This lab creates no shared infrastructure and uses the default VPC without
modifying it, so there is nothing to preserve. **Resources that keep charging if
left:** the ALB (hourly), the four Fargate tasks (hourly), and public IPv4
addresses (hourly, per address).

---

## Cost

Measured, not estimated — unblended cost for 2026-10-24 UTC, the single day the
lab existed:

| Usage type | Cost |
|---|---|
| `USE1-ActionMinute` (FIS) | **$1.0250** |
| `USE1-Fargate-vCPU-Hours:perCPU` | $0.0850 |
| `LoadBalancerUsage` | $0.0675 |
| `USE1-PublicIPv4:InUseAddress` | $0.0645 |
| `USE1-Fargate-GB-Hours` | $0.0187 |
| `USE1-PublicIPv4:IdleAddress` | $0.0003 |
| `LCUUsage` | $0.0000 |
| **Total** | **$1.2610** |

Reproduce with [`docs/blog/terminal/13-cost.sh`](docs/blog/terminal/13-cost.sh).

**81% of the bill is FIS action-minutes**, at $0.10 each — and almost all of
those were `aws:fis:wait` padding, not the fault. FIS bills elapsed action time,
not damage done.

**Cost optimisation:** shorten the waits. A FIS *experiment report* is a further
$5 per report and is not used here.

**Free tier:** none of this is free-tier covered at these volumes. The first 10
CloudWatch alarms are free, so the two alarms cost nothing.

---

## Troubleshooting

| Problem | Root cause | Resolution |
|---|---|---|
| Experiment fails: `logs:CreateLogDelivery` denied | FIS experiment logging uses **vended log delivery**, not plain `PutLogEvents` | Grant `CreateLogDelivery`, `Get/Update/Delete/ListLogDeliveries`, `DescribeResourcePolicies`, `DescribeLogGroups` |
| Experiment fails: "does not have sufficient privileges to set up logging for the specified CloudWatch LogGroup" | `logs:PutResourcePolicy` is **account-level** and cannot be scoped to a log-group ARN | Grant it on `resources = ["*"]` |
| Experiment `completed` but nothing was stopped | FIS resolves its target set **once**, at experiment start; later repeated actions hit already-stopped tasks | Expect only the first round of a repeated fault to do anything |
| Experiment targets nothing at all | Tasks do not inherit service tags | `propagate_tags = "SERVICE"` |
| Alarm never fires during an obvious outage | Alarm is on `UnHealthyHostCount`, which cannot see a deregistered task | Alarm on `HealthyHostCount < desired`, statistic `Minimum` |
| HCP run says "no changes" after you pushed a fix | API-created run reused the last **ingested** configuration version | Pin `configuration-version` to the commit SHA |

---

## References

- [AWS FIS actions reference](https://docs.aws.amazon.com/fis/latest/userguide/fis-actions-reference.html) — which actions have a duration, and which need an SSM agent
- [Stop conditions for AWS FIS](https://docs.aws.amazon.com/fis/latest/userguide/stop-conditions.html)
- [AWS FIS pricing](https://aws.amazon.com/fis/pricing/)
- [`aws_fis_experiment_template`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/fis_experiment_template) — Terraform provider
- [`docs/FINDINGS.md`](docs/FINDINGS.md) — the four findings with full evidence
