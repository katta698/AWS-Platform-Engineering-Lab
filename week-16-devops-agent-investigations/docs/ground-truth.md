
## Break at 2026-08-26T15:57:15Z

| | |
|---|---|
| **What was done** | Detached inline policy `config-read` from role `week16-agent-processor` |
| **Effect** | `week16-agent-processor` loses `ssm:GetParameter` and throws AccessDeniedException on every invocation |
| **What did NOT change** | function code, package hash, environment variables, the SSM parameter itself, the schedule, the alarm |
| **CloudTrail event** | `DeleteRolePolicy` on `week16-agent-processor` |
| **Expected symptom** | Lambda Errors > 0 within ~5 minutes; alarm `week16-agent-processor-errors` to ALARM |

**Grade the agent against this.** A correct answer names the policy
detachment. Naming the AccessDeniedException is the symptom, not the cause,
and should be marked as such.

**Repaired at 2026-08-26T17:24:42Z** — `config-read` restored on `week16-agent-processor`.


## DECOY TEST

A real Terraform deploy landed at **2026-08-26T17:27:38Z**, changing the
processor timeout from 15s to 20s. It is entirely innocent -- the timeout has
nothing to do with the failure.

The break below follows it by a few minutes, so the deploy is the more RECENT
and more ATTRACTIVE explanation. A correct answer still names the IAM policy
deletion; naming the deploy is a failure, and so is hedging between the two
without ranking them.


## Break at 2026-08-26T17:28:49Z

| | |
|---|---|
| **What was done** | Detached inline policy `config-read` from role `week16-agent-processor` |
| **Effect** | `week16-agent-processor` loses `ssm:GetParameter` and throws AccessDeniedException on every invocation |
| **What did NOT change** | function code, package hash, environment variables, the SSM parameter itself, the schedule, the alarm |
| **CloudTrail event** | `DeleteRolePolicy` on `week16-agent-processor` |
| **Expected symptom** | Lambda Errors > 0 within ~5 minutes; alarm `week16-agent-processor-errors` to ALARM |

**Grade the agent against this.** A correct answer names the policy
detachment. Naming the AccessDeniedException is the symptom, not the cause,
and should be marked as such.

**Repaired at 2026-08-26T17:53:18Z** — `config-read` restored on `week16-agent-processor`.


---

## Grading

### Investigation 1 — `2026-08-26T16:44:00Z` — **PASS**

Named the `DeleteRolePolicy` on `week16-agent-processor` as the cause, with the
principal and the timestamp. Treated the AccessDeniedException as the symptom.
Only one change existed in the window, so this establishes the floor, not the
ceiling.

### Investigation 2, the decoy — `2026-08-26T17:36:25Z` — **PASS**

Same prompt, word for word. The innocent `timeout 15 -> 20` deploy landed 71
seconds before the true cause and was never named as a cause.

The answer went further than the first one did. It reconstructed the full
sequence rather than the most recent change:

| Time (UTC) | What the agent reported | Correct? |
|---|---|---|
| 15:57:32 | `config-read` deleted via AWS CLI | yes — ground truth says 15:57:15, CloudTrail says 15:57:32 |
| 17:24:41 | policy briefly re-added, **1 successful invocation observed** | yes — the repair, and the single manual invoke used to verify it |
| 17:28:59 | deleted again | yes |

The single successful invocation between the repair and the re-break was not in
the prompt and is not visible in the alarm. It came out of correlating
CloudTrail with the invocation record.

**One caveat worth stating plainly.** The decoy was a Lambda *timeout* change,
which is a weak decoy: the failure signature is `AccessDeniedException`, not a
timeout, so nothing about the symptom points at it. A stronger test would change
something in the same failure domain — the SSM parameter name, or the
`RECORDS_BUCKET` value. This run shows the agent is not naively
recency-ranking. It does not show it can resolve two plausible permission-shaped
causes.

**Its mitigation was better than the one written here.** Alongside re-adding the
policy it proposed an SCP denying manual deletion of Terraform-managed policies
— that addresses the recurrence, which the restore alone does not.

### Alarm recovery

Restored `17:53:18Z`, alarm returned to OK at `17:58:34Z` — 5m16s, one
evaluation period. The 300-second period was chosen so recovery is observable;
Week 15's 86400/Maximum alarm latched and never re-notified.
