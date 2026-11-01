# Week 25 — Serverless Microservices: The Pool You Did Not Know You Shared

**Reproducible lab guide.** The companion article explains the problem and the
findings; this file is what you run.

**What you build:** three Lambda-backed microservices behind one HTTP API,
sharing one DynamoDB table — and one account-wide Lambda concurrency pool.

**What you learn:** whether a service boundary is a failure boundary.

| | |
|---|---|
| **Difficulty** | Intermediate |
| **Region** | `us-east-2` — deliberately, see [The fence](#the-fence) |
| **Provisioning** | Terraform via HCP Terraform with OIDC |
| **Cost shape** | No hourly meter. Per-request only; the load test dominates |

> **Status:** built and validated. Measured cost and run results are in the
> article; this guide is the procedure.

---

| | |
|---|---|
| **Cost** | $0.81 measured |
| **Provisioning** | Terraform · HCP · Lambda · API Gateway · DynamoDB · CloudWatch |

## 1. Prerequisites

| Requirement | Detail |
|---|---|
| AWS account | Permission for Lambda, API Gateway v2, DynamoDB, IAM, CloudWatch |
| AWS CLI | v2, authenticated (`aws sts get-caller-identity` must succeed) |
| Terraform | >= 1.10 |
| HCP Terraform | A workspace with an AWS OIDC role — no static keys |
| Python | 3.11+, for the load generator and summariser |
| **An empty region** | See [The fence](#the-fence). Non-negotiable |

### Quotas that shape the design

```bash
aws lambda get-account-settings --region us-east-2 \
  --query 'AccountLimit.{concurrency:ConcurrentExecutions,unreserved:UnreservedConcurrentExecutions}'
```

| Quota | Default | Why it matters |
|---|---|---|
| Concurrent executions | **1,000** | The shared pool. The whole lab |
| Reservable at function level | **900** | AWS always keeps 100 for unreserved functions |
| Requests per second | **10× concurrency** | 10,000 default — a sub-100ms function hits this *before* it exhausts concurrency |

**No prerequisite labs.** Week 25 is self-contained.

---

## 2. Source files

| File | Purpose |
|---|---|
| [`terraform/environments/dev/main.tf`](terraform/environments/dev/main.tf) | HCP backend, OIDC, region choice and its reasoning |
| [`terraform/modules/service/main.tf`](terraform/modules/service/main.tf) | The three services, the API, the table — **and the control variable** |
| [`terraform/modules/experiment/main.tf`](terraform/modules/experiment/main.tf) | Throttle alarms and the concurrency dashboard |
| [`src/*/handler.py`](src/) | Three handlers, identical but for `DURATION_MS` |
| [`scripts/run-experiment.py`](scripts/run-experiment.py) | Drives load, records checkout from the client side |
| [`scripts/summarise.py`](scripts/summarise.py) | Turns recordings into the success-rate comparison |

### The control variable

One attribute decides the whole experiment, and it lives on the function
because reserved concurrency is an *attribute*, not a resource:

```hcl
reserved_concurrent_executions = (
  var.protect_checkout && each.key == "checkout"
  ? var.checkout_reserved_concurrency   # run 2
  : -1                                   # run 1: shares the pool
)
```

**Run 1** leaves everything unreserved. **Run 2** reserves 50 for `checkout`.
Nothing else changes — same load, same code, same region.

### Why duration, not request rate

Concurrency is `requests per second × duration`. The neighbours are slow
(500 ms) rather than merely frequent, because a 500 ms function consumes **ten
times** the pool of a 50 ms one at the same request rate. `checkout` runs at
50 ms, so each of its execution environments serves ~20 requests/second.

---

## 3. Deploy

```bash
cd terraform/environments/dev
terraform init
terraform plan      # run 1: protect_checkout defaults to false
terraform apply
```

Through HCP, pinned to the commit you actually pushed:

```bash
python ../../../scripts/hcp_apply_pinned.py week-25-dev --apply
```

That path runs `check_before_deploy.py` first and **refuses** if the
before-state figures have not been captured. A deploy is the point of no
return for them.

### Validation checkpoint — deployed is not working

```bash
API=$(terraform output -raw api_endpoint)
curl -s -X POST "$API/checkout" -d '{}' -H 'content-type: application/json'
# expect: {"service":"checkout","key":"checkout#...","held_ms":5x,...}

aws lambda get-function-concurrency --function-name week25-microservices-checkout \
  --region us-east-2
# run 1: ReservedConcurrentExecutions absent -- it shares the pool
```

---

## 4. Run it

**Run 1 — checkout unprotected:**

```bash
python scripts/run-experiment.py --label run1-unprotected
```

60 seconds of clean baseline, then both neighbours ramp on. The recorder
refuses to start if `--label` disagrees with the deployed `protect_checkout`,
so a run cannot be filed under the wrong name.

**Run 2 — checkout reserved:**

```bash
cd terraform/environments/dev
terraform apply -var protect_checkout=true
cd ../../..
python scripts/run-experiment.py --label run2-protected
```

**Compare:**

```bash
python scripts/summarise.py results/*.csv
```

---

## 5. Validation

### What to look for

| Signal | Where | Means |
|---|---|---|
| `Throttles` > 0 on checkout | CloudWatch, `AWS/Lambda` | Lambda refused to start it |
| 502 at the client | the recorder's CSV | What the caller saw |
| Nothing in checkout's logs | CloudWatch Logs | **The point** — a throttled invocation never ran |

**A throttled invocation leaves no trace inside the function that suffered
it.** No log line, no exception, nothing to catch. That is why the measurement
is taken from the client and the alarm is on `Throttles`.

```bash
aws cloudwatch get-metric-statistics --namespace AWS/Lambda \
  --metric-name Throttles --statistic Sum --period 60 \
  --dimensions Name=FunctionName,Value=week25-microservices-checkout \
  --start-time <run start> --end-time <run end> --region us-east-2
```

---

## 6. Cleanup

```bash
cd terraform/environments/dev
terraform destroy
```

Or through HCP, so teardown is a traceable run:

```bash
python ../../../scripts/hcp_destroy.py week-25-dev --message "Teardown: week 25"
```

### Verify — do not trust the destroy output

```bash
bash docs/blog/terminal/10-destroyed.sh
```

Queries Lambda, API Gateway, DynamoDB, IAM, CloudWatch alarms and log groups in
**us-east-2** for anything named `week25`. All should return empty.

**Nothing here is shared** and the default VPC is not used, so there is nothing
to preserve. **Nothing bills hourly either** — but the DynamoDB table and the
log groups persist and will hold data until removed.

---

## Cost

| Usage type | Quantity | Cost |
|---|---|---|
| API Gateway HTTP requests | 798,228 | $0.798228 |
| DynamoDB write request units | 21,446 | $0.013404 |
| Lambda requests and duration | 21,446 requests, 30,056 GB-seconds | $0.00 |
| **Total** |  | **$0.81** |

The protection in run 2 cost $0.00.

## Troubleshooting

**An early run showed checkout falling to 2% success under load. It looked exactly like the result the lab was built to produce**.
It was the client dying, not the service. The failures were connection errors rather than HTTP 503s, they began ten seconds *before* the neighbours ramped on, and CloudWatch recorded zero throttles on all three functions with the pool peaking at 292 of 1,000.
*Fix:* Change the success criterion from a success-rate curve to `Throttles` in CloudWatch, then re-run.

**Two attempts failed to exhaust the pool, peaking at 319 and 292 concurrent executions with no throttling at all**.
Concurrency is requests per second times duration, so occupying 1,000 slots means holding 1,000 requests open simultaneously. The original generator started a thread per request and delivered 13 requests a second when asked for 60. Rewriting it in asyncio — coroutines holding keep-alive connections, working in concurrency rather than request rate — raised the ceiling and still fell short.
*Fix:* Stop trying to fill the pool and shrink it instead: reserve 900 to a neighbour, and AWS leaves exactly 100 unreserved for the others to contend over.

**Setting checkout's reservation to 50 while lowering a neighbour's from 900 to 850 failed: `InvalidParameterValueException: Specified ReservedConcurrentExecutions for function decreases account's UnreservedConcurrentExecution below its minimum value of [100]`**.
Terraform applied checkout's increase before the neighbour's decrease. The requested end state totals 900 reserved and is perfectly legal; the intermediate state asked for 950 and breached the account floor.
*Fix:* Two applies — lower first, then raise.

## References

- [Understanding Lambda function scaling](https://docs.aws.amazon.com/lambda/latest/dg/lambda-concurrency.html) — the shared pool, reserved vs provisioned, the 10× requests-per-second rule
- [Lambda quotas](https://docs.aws.amazon.com/lambda/latest/dg/gettingstarted-limits.html)
- [`aws_lambda_function`](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) — Terraform provider
- [API Gateway HTTP API pricing](https://aws.amazon.com/api-gateway/pricing/)

## The fence

**Read this before running anything.**

Lambda's concurrency limit is per account **and per region**: 1,000 concurrent
executions by default, shared by every function that has no reservation.

This lab deliberately exhausts that pool. Run it in a region where other things
live and you will throttle them. Measured in this account before choosing:

```bash
aws lambda list-functions --region us-east-1 --query 'length(Functions)'   # 13
aws lambda list-functions --region us-east-2 --query 'length(Functions)'   # 0
```

So it runs in **us-east-2**, where the entire unreserved pool belongs to the
experiment. **Check your own account before you copy this** — your empty region
may not be the same as mine.

```bash
# find a region with nothing in it
for r in us-east-2 us-west-2 eu-west-1; do
  echo "$r: $(aws lambda list-functions --region $r --query 'length(Functions)' --output text)"
done
```

---

## Known limitations

- **One account, one region, one pool.** The lab proves starvation *within* a
  region. Cross-region isolation is asserted from the documented quota model,
  not measured here.
- **Reserved concurrency is a floor and a ceiling.** Run 2 protects `checkout`
  and simultaneously caps it — it can no longer borrow from the unreserved
  pool. The lab shows the protection; it does not explore the cap.
- **Not production-ready.** No authentication on the API, no WAF, no custom
  domain. The services exist to consume concurrency, not to be a reference
  application.
