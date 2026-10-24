# Week 24 findings — four ways a chaos experiment reports success while proving nothing

Every finding below is a measurement, not a reading of the documentation. Each
one was invisible in the FIS console, which showed `completed` throughout.

The lab: one ECS Fargate service, 4 tasks, behind an ALB. Two CloudWatch
alarms watching the same metric with different patience (60s/1 datapoint vs
300s/2 datapoints), wired as FIS stop conditions. The intended headline was
"the slower alarm costs you N minutes of damage."

That headline could not be measured, and the reasons are the week.

---

## 1. An alarm on `UnHealthyHostCount` can never fire for a stopped ECS task

The obvious metric for "my tasks are dying" does not move when your tasks die.

When FIS stops an ECS task, ECS **deregisters** it from the target group.
`UnHealthyHostCount` counts targets that are registered *and* failing their
health check. A deregistered target is not unhealthy — it is absent. So
capacity halves while the metric sits at exactly zero.

Measured, baseline run at 22:56 CDT:

| minute | HealthyHostCount (Min) | UnHealthyHostCount (Max) |
|---|---|---|
| 22:55 | 4.0 | 0.0 |
| **22:56** | **2.0** | **0.0** |
| 22:57 | 4.0 | 0.0 |

The service demonstrably halved. `UnHealthyHostCount` reported `0.0` for every
datapoint across the entire window.

Both stop conditions were built on this metric. Both were unreachable — not
slow, not badly tuned: **structurally incapable of ever firing.** A console
screenshot of either alarm shows a healthy green `OK`, which is exactly what
it would show if it were working.

Fix: alarm on `HealthyHostCount < desired_count`, statistic `Minimum`.
`Minimum` and not `Average`, because over a 300s window a one-minute dip
averages to ~3.6 and never crosses a threshold of 4.

## 2. `aws:ecs:stop-task` is instantaneous, so a stop condition on it is decorative

A stop condition stops an *experiment*. It cannot stop an experiment that has
already ended.

Measured, from the FIS API:

```
action  : stop-tasks  (aws:ecs:stop-task)
start   : 2026-10-23T22:56:30.862
end     : 2026-10-23T22:56:31.235
         -> 373 milliseconds
```

No CloudWatch alarm evaluates in 373ms. The fastest possible alarm here is
60 seconds. The guarded experiments would have run to completion every time,
both stop conditions untriggered, both runs reporting `completed` — two
identical null results that look exactly like two successful experiments.

This is also why "add a stop condition" is not by itself a safety measure.
The action has to have a **duration** for a stop condition to mean anything.
Of the ECS actions, only the `aws:ecs:task-*` family does, and every one of
them requires SSM-managed tasks (a sidecar on Fargate).

## 3. FIS resolves its targets once, at experiment start

To give the fault a duration, the experiment was rebuilt to deliver it in
rounds: 7 × `aws:ecs:stop-task` separated by 6 × `aws:fis:wait` of `PT2M`.

All six rounds fired exactly on schedule. All six reported
**"Action was completed."** Only the first one stopped anything:

```
23:28:06  stop-tasks-1  completed   ->  2 tasks stopped
23:30:08  stop-tasks-2  completed   ->  0
23:32:10  stop-tasks-3  completed   ->  0
23:34:12  stop-tasks-4  completed   ->  0
23:36:14  stop-tasks-5  completed   ->  0
23:38:16  stop-tasks-6  completed   ->  0
```

Five consecutive green actions that did nothing at all.

This is **not** a tag-propagation failure, which was the first suspicion. The
service sets `propagate_tags = "SERVICE"`, and the replacement tasks started
at 23:28:45 and 23:28:47 both carry `FISTarget=week24-chaos`. Verified
directly:

```
started 23:28:47.399   tags: ["week24-chaos"]   <- replacement
started 23:28:45.903   tags: ["week24-chaos"]   <- replacement
started 22:41:16.885   tags: ["week24-chaos"]
started 22:40:53.628   tags: ["week24-chaos"]
```

The targets were correctly taggable. FIS simply resolved the target set at
t=0 and held it. Rounds 2–6 re-issued `StopTask` against two task IDs that
had already stopped, and `StopTask` on an already-stopped task succeeds.

Consequence for anyone designing a long FIS experiment: **a repeated action
does not re-select its targets.** If the fault is one the platform heals
from, every round after the first is a no-op that reports success.

## 4. The platform healed faster than the metric could be sampled

The most uncomfortable one.

ECS replaced the two killed tasks in about 40 seconds:

```
23:28:06   FIS issues StopTask
23:28:45   replacement task running
23:28:47   replacement task running
```

The per-second recorder watched the ALB go to 2 healthy at t=28s and back to
4 healthy at t=45s — a real, observed, ~17-second capacity outage.

CloudWatch's 1-minute `Minimum` for `HealthyHostCount` across that window:

```
23:26  4.0
23:27  4.0
23:28  4.0     <- the outage is inside this minute
23:29  4.0
23:30  4.0
```

**The dip never appeared in the metric at all.** ALB publishes host counts as
periodic samples; a 17-second dip fell between them.

And it is not deterministic. The 22:56 baseline run — same fault, same
service, same metric — *did* record a `2.0`. Same outage, observed once and
missed once.

So no alarm on this metric could have fired reliably, at any period, for this
fault. Not because the alarm was wrong, but because **the service recovered
faster than its own observability could sample it.** The resilience was real;
the ability to prove it was not.

---

## What this means for the original question

"How much more damage does a slow alarm let through?" is unanswerable on this
workload, and the reason is worth more than the answer would have been: the
fault heals in 17 seconds, the metric samples every 60, and the action
completes in 373 milliseconds. There is no window in which a stop condition —
fast or slow — could have acted.

A chaos experiment that cannot fail is not a test. Every one of the four
defects above presented in the console as a green, completed, successful run.

## Tooling defects found alongside

- **The recorder stopped watching before the damage landed.** FIS reports
  `completed` when its last action *returns*, not when the fault has played
  out. On the baseline run FIS said completed at 22:56:31; ECS started
  replacements at 22:57:08 and the originals did not reach `STOPPED` until
  22:57:41 — 70 seconds after the experiment was officially over. The first
  version of the runner exited on the terminal state and recorded a flat line
  of 4 healthy targets through a run that halved the service. It now keeps
  sampling through an `aftermath` phase until the service is whole again.

- **16-second sampling resolution.** Four AWS calls run serially took ~11s,
  plus a 5s sleep. Timing a 60s alarm against a 300s one at 16s granularity
  is not a measurement. The calls now run in parallel at a 2s interval.

- **Starting a run against an already-tripped alarm.** A stop condition
  already in `ALARM` stops the experiment at t=0; FIS reports `stopped` and
  the run looks like an instant, heroic save of the previous run's damage.
  The typical alarm stays tripped for ten minutes after recovery, so
  back-to-back runs hit this. The runner now refuses to start.

- **An HCP run can apply code you did not push.** Creating a run via the API
  without naming a configuration version makes HCP reuse the last one it
  ingested. It reported `planned_and_finished` — "no changes" — while the
  broken IAM policy it was meant to fix was still live. `hcp_apply_pinned.py`
  now waits for the configuration version whose commit sha matches `HEAD` and
  refuses to run if it never arrives.
