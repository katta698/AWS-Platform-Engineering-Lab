# Week 28 — The Failover Nobody Runs

**What you build:** a PostgreSQL primary in us-east-1, a cross-region read
replica in us-west-2, and the failover runbook declared as an ARC Region
switch plan — then you run it and time it.

| | |
|---|---|
| **Cost** | **$0.3731 measured** (RDS $0.2412, ARC plan $0.1319) |
| **Provisioning** | Terraform ≥ 1.10, AWS provider ≥ 6.47, HCP workspace `week-28-dev` |
| **Regions** | us-east-1 (primary) and us-west-2 (replica) |

> **Status:** built, validated and destroyed 2026-11-17. Published 2026-11-18.

Every disaster recovery document contains a recovery time. Almost none contain
a measurement, because promoting a read replica destroys it: the replica
becomes a standalone database that no longer replicates, and there is no way
back. Rehearsing the procedure costs you the thing the procedure protects.

This lab runs it anyway, and records two numbers: how far behind the replica
actually was, and how long the failover actually took.

**Measured:** the database was serving as a standalone primary **160 s** after
`PromoteReadReplica` was called; the Region switch plan did not report itself
complete for **726 s**, because it waits out an automatic post-promotion
backup. Replication lag **20 s peak / 4.2 s average** under a 6.4-million-row
write load.

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
page does, and figure 04 needs the stack alive.

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

Then read the database's own record, because the script's clock and the
database's are not the same clock:

```bash
aws rds describe-events --region us-west-2 \
  --source-identifier week28-failover-replica --source-type db-instance \
  --duration 1440 --query 'Events[].[Date,Message]' --output text
```

`DB instance restarted` is when it was usable. Everything after that is RDS
taking a backup.

## 6. Cleanup

```bash
bash scripts/cleanup.sh
```

Refuses while a declared figure is uncaptured, then destroys both regions and
asks the API — including snapshots and the Region switch plan.

Snapshots are checked because deleting a database does not delete them, and
the bill for them goes UP afterwards. The free backup allowance is 100% of
the storage you have provisioned in that region, so a snapshot sitting beside
a live 20 GB database is usually free; delete the database and the allowance
goes with it, leaving the snapshot billable at $0.095/GB-month. AWS also
attributes those charges to the snapshot's own ARN rather than the instance,
so nothing in the bill still carries the name you would search for. This lab
sets `skip_final_snapshot = true` and does not retain automated backups, so
there should be none — the check is there to prove it.

**Check:** `Teardown verified in both regions.`

---

## Cost

**Measured: $0.3731** for 18 Nov UTC, the day the lab ran.
<!-- COST_MEASURED_ON: 2026-11-19 COST_STABLE_OVER: 7h -->
Read 2026-11-19 at 12:45 UTC and again at 20:05 UTC, unchanged.

| Line | Cost |
|---|---|
| Amazon RDS (2 x db.t4g.micro + storage) | $0.2412 |
| ARC Region switch plan | $0.1319 |

The plan line answers this week's open question. AWS publishes "$70 per plan
per month", "prorated for partial months", without defining partial. The bill
is explicit: usage type `Global-AmazonARCRegionSwitchPlan`, quantity
**0.001885 Months**, implied rate **$70.0000 per month**. That quantity is
81.4 minutes; CloudTrail puts the plan's life at 81 minutes 26 seconds
(`CreatePlan` 22:13:25, `DeletePlan` 23:34:51 CST). Metered to the minute at
the published rate, so rehearsing a failover costs cents while keeping a plan
costs $840/year per application.

**Read it a day late, and read it twice.** Taken five minutes after the UTC
day closed, this same day reported $0.2359 — 58% low, with the ARC line at
$0.0755 and RDS at $0.1604. Cost Explorer keeps filling a day in for hours
after it ends. Cost Explorer also bills in UTC days, so an evening run in CST
lands on the NEXT UTC day: this lab ran the evening of 17 Nov local and every
line of it was billed to 18 Nov UTC.

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
