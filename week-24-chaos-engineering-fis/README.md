# Week 24 — Chaos engineering with AWS FIS

**The story:** you attach a CloudWatch alarm to a fault injection experiment as
a stop condition, and you feel safe. The experiment will halt itself if real
damage starts. But an alarm cannot fire faster than its own evaluation window,
so the safety net has a hole in it the exact size of that window — and almost
nobody measures how big it is.

**What it builds:** one ordinary ECS Fargate service behind an ALB, two
CloudWatch alarms watching the same metric with different patience, and three
FIS experiments that inject the same fault under different guards.

## Architecture

```
    ALB  ->  target group  ->  4 Fargate tasks
                  |
                  +-- UnHealthyHostCount
                         |
            +------------+------------+
            |                         |
     alarm "fast"              alarm "typical"
     60s / 1 datapoint         300s / 2 datapoints
     fires in ~1 min           cannot fire under 10 min
            |                         |
            +----------+--------------+
                       |
                 FIS stop condition
                       |
            aws:ecs:stop-task  (50% of tasks)
```

## The three experiments

| Label | Stop condition | Question |
|---|---|---|
| `recovery` | none | How long does ECS take to heal by itself? |
| `fast` | 60s / 1 datapoint alarm | How quickly does the net close? |
| `typical` | 300s / 2 datapoint alarm | How much longer does the damage run? |

`fast` and `typical` are generated from one `for_each`, so they are identical
except for the alarm. Any difference in the result is attributable to the alarm
and nothing else.

## Running it

```bash
cd terraform/environments/dev
terraform init && terraform apply

# confirm it is actually serving before breaking it
curl -s -o /dev/null -w '%{http_code}\n' "$(terraform output -raw alb_url)"

cd ../../..
bash scripts/run-experiment.sh recovery
bash scripts/run-experiment.sh fast
bash scripts/run-experiment.sh typical

python scripts/summarise.py results/*.csv
```

Each run records a CSV per second: FIS state, healthy and unhealthy targets,
and both alarm states. The post quotes measurements, not impressions.

## Two things worth knowing before you plan a chaos day

**The interesting FIS actions need a sidecar.** Every `aws:ecs:task-*` action —
CPU stress, network latency, IO stress — requires the tasks to be *managed by
AWS Systems Manager*, which on Fargate means adding an SSM agent container to
the task definition. `aws:ecs:stop-task` goes through the ECS API and needs
nothing. Scope accordingly.

**A task does not inherit its service's tags.** FIS targets by tag. Without
`propagate_tags = "SERVICE"` on the ECS service, the experiment matches nothing,
reports success, and the service stays up — a green run that proved nothing,
which is the worst outcome a chaos experiment can produce.

## Cost

| | |
|---|---|
| FIS | $0.10 per action-minute |
| Fargate | 4 × 0.25 vCPU / 0.5 GB |
| ALB | ~$0.54/day plus LCU |
| Experiment reports | **not generated** — $5 each, and the CSV has the same facts |

Expected around $7–8 for the week. Read from the bill after teardown, not from
this table.

## Security

- The FIS role can stop tasks **in one cluster** and nothing else. It cannot
  break what it cannot reach, which is containment before any stop condition
  is involved.
- The trust policy is scoped by `aws:SourceAccount` and `aws:SourceArn` to
  experiments in this account — the standard confused-deputy guard.
- No static credentials anywhere; HCP Terraform authenticates with OIDC.

## Teardown

```bash
cd terraform/environments/dev && terraform destroy
```

Then verify against AWS rather than against the destroy output — the cluster,
the ALB and the experiment templates should all be gone.
