# Week 16 — AWS DevOps Agent: Investigations, and Whether to Believe Them

**The story:** an investigating agent does not return a metric. It returns a **narrative** — *"the IAM change at 14:02 removed the parameter read, here is the evidence."* Narratives are persuasive whether or not they are correct, and that is the whole problem with putting one on-call.

So this week is not a demonstration that an agent can investigate. AWS's marketing covers that. It is an **evaluation**: break something in a known way, let the agent investigate with no hints, and grade its conclusion against Week 15's CloudTrail attribution — which is fact rather than opinion.

---

## What makes this gradeable

Week 15 built an organization trail and seven forensic queries that answer *who did what, when, from where*. That is ground truth. Week 16 produces a claim. Having both in the same account is what turns "the agent seemed clever" into "the agent was right about two of three, and confidently wrong about the third."

The deliberate break is chosen to make that comparison sharp:

> **Revoke `ssm:GetParameter` from the running workload's execution role.**

Nothing about the deployment changes — same code, same configuration, same image. The function simply starts failing. Every obvious place to look is clean, and the true cause is a single IAM event that CloudTrail records with a principal, a timestamp and a source IP.

---

## Verified before building

Everything here was checked against the live API on 2026-08-26, not read from documentation.

| Question | Answer |
|---|---|
| Usable on a **Basic** support plan? | **Yes** — `list-agent-spaces` returns cleanly. Paid plans get usage *credits*, not access |
| Native `aws_devopsagent_*` Terraform resources? | **No** — provider issue [#46894](https://github.com/hashicorp/terraform-provider-aws/issues/46894) still open |
| Available via `awscc`? | **Yes** — six resources, because awscc generates from the CloudFormation registry |
| Built-in spend ceiling? | **None.** The schema has no budget, duration or task limit |
| Does an idle agent space bill? | **No** — verified at 0.0 on every usage meter |
| Cost of the exploratory probe | **$0.00** |

---

## The service is newer than its Terraform provider

This is the week that collides with the series' own rule of *always HCP Terraform, always IaC*. The `hashicorp/aws` provider has no DevOps Agent resources — scanning the installed v6.60.0 binary finds `aws_devopsagent_` as a bare prefix with nothing behind it.

**`awscc` is the answer**, and it is worth understanding why rather than treating it as a workaround. It generates resources from CloudFormation's registry, so a service appears there as soon as its CFN types go LIVE — no waiting for someone to hand-write a provider resource.

The trade is real: awscc resources are machine-generated, so they carry CloudFormation's shapes and naming rather than the ergonomics of hand-written ones, and the documentation is thin. That is the price of being early.

---

## Cost — the honest position

**$0.0083 per agent-second of active work.** $0.50 a minute. No idle charge, no fixed fee, no ceiling.

Every previous week in this series leaned on a service-enforced limit — Weeks 14 and 15 both capped Athena at 10 GB per query at the workgroup level, so a mistake was bounded by *configuration*. There is no equivalent here. The only lever is a concurrency quota, and it bounds how **many** tasks run, never how **long** one runs.

So the control is observation:

```bash
./scripts/measure_usage.sh
```

Reads the usage meter, converts hours to dollars, and prints the absence of a limit rather than hiding it. **Run it before and after anything the agent does.**

A free trial exists — 2 months, 20 hours of investigations per month — for new DevOps Agent customers. Whether it applies here is not yet confirmed; it appears as a billing credit, not as a usage limit, so it cannot be read from the API.

---

## Prerequisites

**ServiceNow OAuth credentials.** There is no Terraform path — the same shape as Week 6's SCP policy-type enablement and Week 15's CloudTrail trusted access:

> ServiceNow → **System OAuth** → **Application Registry** → *Create an OAuth API endpoint for external clients*

Take the Client ID and Client Secret into HCP workspace variables, marking the secret sensitive.

**Wake the instance first.** A ServiceNow developer instance hibernates after roughly ten days idle. When asleep it fails registration in a way that reads like a credentials problem rather than a sleep problem.

---

## Status

Scaffolded and `terraform validate` clean. Not yet deployed.

**Still to build:** the ServiceNow service registration and association, the deliberate-break script, verification and cleanup scripts, and the grading comparison against Week 15's queries.
