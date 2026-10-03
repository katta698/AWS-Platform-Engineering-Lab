# Week 21 — Blue/Green on ECS

Deploy a new version of a container with no downtime, and get the old one back
automatically when the new one is bad. The deployment controller is ECS itself — no
CodeDeploy, because AWS recommends the native path for new work as of March 2026.

**Blog:** https://jayanthkatta.com/blog/week-21-bluegreen-ecs/

## What it builds

16 AWS resources. Only the two target groups exist because of blue/green; the rest is what
any container behind a load balancer needs.

| What | Count | Its job |
|---|---|---|
| ALB, listener, listener rule | 3 | The front door. ECS rewrites the *rule* to switch versions |
| Target groups — blue and green | 2 | The two slots a version can occupy |
| ECS cluster, task definition, service | 3 | Runs the container on Fargate; the service carries the strategy |
| Security groups | 2 | Public HTTP to the ALB; the ALB only to the tasks |
| CloudWatch log group, alarm | 2 | Task logs, and the 4xx alarm wired to roll back |
| IAM roles + policy attachments | 4 | One pulls the image and writes logs; the other lets ECS rewrite the listener rule |

HCP Terraform reports 20 — its count includes four data sources.

## What it found

**A deliberately broken release reached zero users — and the alarm never fired.** Its tasks
failed the target group health check (`Target.ResponseCodeMismatch`, "codes: [404]"), so no
client request ever reached them, so there were no 4xx to alarm on. 214 requests during the
attempt, all served by the previous version.

Users were protected by the health check, not by the rollback. **Testing rollback with a
fault your health check catches tests the health check.**

Three smaller ones:

- `deploymentCircuitBreaker` is **off by default** — the failing deployment retried for 10+
  minutes instead of reverting.
- `terraform apply` returned **applied** with zero new tasks running and the old version
  still serving. It hands off to ECS and returns.
- `AmazonECSInfrastructureRolePolicyForLoadBalancers` has **no `/service-role/` path**,
  unlike `AmazonECSTaskExecutionRolePolicy`. ECS reports the missing attachment as "Unable
  to assume role and validate the specified targetGroupArn".

The good release: cutover visible to a client at **t+182s**, 62 requests on v1, 86 on v2,
zero failures. A straight switch, not a percentage split — one task plus plain `BLUE_GREEN`
just flips the listener rule.

## Running it

Provider must be **>= 6.4**. On 6.0–6.3 the `deployment_configuration` block is silently
ignored and you get a rolling update that still reads correctly in the file.

```bash
# deploy, then watch a release from the client's side
URL="http://<alb-dns>/" bash scripts/watch_shift.sh

# after the destroy
bash scripts/cleanup.sh
```

## Cost

**Billed $0.1552** for about three hours — Elastic Load Balancing $0.1126, ECS/Fargate
$0.0425, and $0.00 the day after teardown. **The load balancer was 73%**, for a service
that served a few hundred requests: the meter is the front door, not the containers.

Destroyed and verified: no load balancer, cluster, target groups or network interfaces
remain, and the workspace reports zero resources.
