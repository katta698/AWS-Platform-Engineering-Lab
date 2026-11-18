# Week 28 — The Failover Nobody Runs

**What you build:** a PostgreSQL primary in us-east-1, a cross-region read
replica in us-west-2, and the failover runbook declared as an ARC Region
switch plan — then you run it and time it.

| | |
|---|---|
| **Cost** | COST_PENDING |
| **Provisioning** | Terraform ≥ 1.10, AWS provider ≥ 6.47, HCP workspace `week-28-dev` |
| **Regions** | us-east-1 (primary) and us-west-2 (replica) |

> **Status:** built, measured and destroyed 2026-11-17.

Every disaster recovery document contains a recovery time. Almost none contain
a measurement, because promoting a read replica destroys it: the replica
becomes a standalone database that no longer replicates, and there is no way
back. Rehearsing the procedure costs you the thing the procedure protects.

This lab runs it anyway, and records two numbers: how far behind the replica
actually was, and how long the failover actually took.

**Measured:** failover **726 s (12.1 minutes)**, replication lag **20 s peak /
4.2 s average** under a 6.4-million-row write load.

---

## 1. Prerequisites

- An AWS account with permission to create RDS instances in two regions.
- Terraform ≥ 1.10 and the **AWS provider ≥ 6.47** —
  `rds_promote_read_replica_config` landed in that release.
- An HCP Terraform workspace with AWS dynamic credentials
  (`TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN`).
- A default VPC in both regions, or your own subnets in at least two AZs each.

**Check:** `terraform version` reports ≥ 1.10, and
`aws rds describe-orderable-db-instance-options --engine postgres
--db-instance-class db.t4g.micro --region us-west-2` returns the engine
version you intend to use.

## 2. Source files

| File | What it is |
|---|---|
| `terraform/environments/dev/main.tf` | Both databases, the ARC plan, the writer function |
| `terraform/environments/dev/variables.tf` | Regions, engine version, and the switch that omits the ARC plan |
| `src/writer/handler.py` | Writes rows to the primary so lag is measurable |
| `scripts/build_package.sh` | Builds the Lambda zip with a Linux `psycopg2` wheel |
| `scripts/run_failover.py` | The measurement: load, lag, then the plan execution |
| `scripts/show_failover.py` | Prints the recorded result without re-running it |
| `scripts/cleanup.sh` | Destroys both regions and verifies against the API |

## 3. Build the package

```bash
bash scripts/build_package.sh
```

`psycopg2` ships compiled extensions, so the wheel must match the Lambda
runtime rather than your machine. The script passes
`--platform manylinux2014_x86_64` and then checks a `.so` is actually present.

**Check:** the script prints `handler.py and psycopg2 present
(_psycopg.cpython-313-x86_64-linux-gnu.so)`. A build without the `.so` imports
fine locally and fails in AWS.

## 4. Deploy

```bash
cd terraform/environments/dev
terraform init
terraform apply
```

Expect **~25 minutes**: the primary takes about 8, and the replica cannot
start building until the primary exists — it took 14 minutes here.

**Check:** `terraform plan` immediately afterwards reports no changes. If it
proposes replacing the replica, see the `storage_encrypted` note in
Troubleshooting before you apply anything.

**Capture now, not later:** figure 01 (the HCP run) exists only while the run
page does, and figures 03 and 04 need the stack alive.

## 5. Run the failover

```bash
cd ../../..
python scripts/run_failover.py
```

This is **one attempt per deployment**. The script refuses to start unless the
replica is confirmed to be replicating, writes for 300 seconds, waits 180
seconds for CloudWatch to publish, reads the lag, and only then executes the
plan.

It writes for five minutes on purpose. `ReplicaLag` on an idle primary is
`now()` minus the last replayed transaction, so it climbs 60 s every minute
while the replica is perfectly caught up. The script rejects any window whose
lag rises in step with the clock, because that is idleness, not replication.

**Check:** the output reports a lag peak and average, then
`plan execution: completed`, then `still replicating: False`. Anything else
and the measurement is not usable.

## 6. Cleanup

```bash
bash scripts/cleanup.sh
```

Refuses while a declared figure is uncaptured, then destroys both regions and
asks the API — including snapshots, which outlive a destroyed instance and
keep charging, and the Region switch plan, which is the only resource here
billed as a flat monthly fee.

**Check:** `Teardown verified in both regions.`

---

## Cost

COST_PENDING

## What is different in production

- **One replica is not a DR plan.** This lab has no automated failback;
  returning to us-east-1 means building a new replica in the other direction
  and promoting it. Budget the rebuild, because that is the real cost of
  testing.
- **`db.t4g.micro` is a lab size.** Promotion time scales with the work the
  instance has to do to come up; measure your own class.
- **The plan has no CloudWatch alarm trigger here.** ARC can execute a plan
  from an alarm; a production plan should say what fires it.
- **Backups are set to one day** to satisfy the replica prerequisite, not
  because one day is a sensible retention.

## Troubleshooting

**The provider's own ARC example does not create.** It shows an `activate`
and a `deactivate` workflow; `CreatePlan` rejects that for `activePassive`
("must not specify target action 'deactivate'"), then demands "activate
workflows defined for each region". Two activate workflows, one per region.

**Declare the primary region's workflow first.** The provider compares
workflows by position while `GetPlan` returns them sorted, so the reverse
order fails the first apply with "block count changed from 0 to 1" and makes
every later plan show the two workflows swapping places.

**AWS's sample IAM policy is incomplete.** Add
`iam:SimulatePrincipalPolicy` — without it the plan sits at "Action required"
and reports both a missing-policy warning and "Region switch does not have
data on DB instance", which read like two unrelated faults. A ManualApproval
step also needs `arc-region-switch:ApprovePlanExecutionStep`. Plan evaluation
is cached and does not re-run promptly, so this is slow to iterate.

**Start an activate flow in the target region.** A client in the primary
region gets "An activate flow should be run on the target region". ARC runs a
data plane in every region precisely so failing over does not call into the
region being evacuated.

**An encrypted cross-region replica needs `storage_encrypted = true`
declared.** RDS sets it for you, so AWS reports `true` while the config says
`null`, and Terraform reads `true -> null # forces replacement`. The first
apply succeeds either way; the second destroys the database.

**Local Zones sort before regular AZs.** `us-east-1-dfw-1a` precedes
`us-east-1a`, and a DB subnet group rejects a Local Zone subnet. Filter
`aws_availability_zones` on `zone-type = availability-zone`.

## References

- [Monitoring read replication](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_ReadRepl.Monitoring.html) — the exact query behind `ReplicaLag`
- [Amazon RDS Promote Read Replica execution block](https://docs.aws.amazon.com/r53recovery/latest/dg/rds-promote-read-replica-block.html)
- [Region switch in ARC](https://docs.aws.amazon.com/r53recovery/latest/dg/region-switch.html)
- [ARC pricing](https://aws.amazon.com/application-recovery-controller/pricing/)
- [Terraform — `aws_arcregionswitch_plan`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/arcregionswitch_plan)
