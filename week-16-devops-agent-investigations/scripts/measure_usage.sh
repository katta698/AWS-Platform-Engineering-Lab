#!/usr/bin/env bash
#
# Read the DevOps Agent usage meter. Run before and after anything the agent does.
#
# This week has no spend ceiling to lean on. Every other week in this series had
# one enforced by the service -- Week 14 and Week 15 both capped Athena at 10 GB
# per query at the workgroup level, so a mistake was bounded by configuration.
#
# An agent space has no equivalent. Its CloudFormation schema carries Name,
# Description, KmsKeyArn, Locale, OperatorApp and Tags, and nothing else: no
# budget, no maximum duration, no task cap. Billing is $0.0083 per agent-second
# of active work -- $0.50 a minute -- and the only thing bounding a runaway is
# the concurrency quota, which bounds how MANY tasks run, never how LONG one runs.
#
# So the control here is observation rather than enforcement. get-account-usage
# reports hours consumed per category for the current calendar month, which makes
# the spend measurable in real time instead of estimated afterwards.
#
# Verified on 2026-08-26 against a throwaway agent space: creating a space costs
# nothing, deleting it costs nothing, and an execution that is created but never
# asked to do work leaves every meter at 0.0. Only actual agent work bills.

set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
RATE_PER_SECOND=0.0083

# Git Bash rewrites leading-slash arguments into Windows paths; harmless here but
# every script in this repo exports it so the habit is never the thing that
# breaks a run. See Week 12 and Week 15 for two occasions it did.
export MSYS_NO_PATHCONV=1

usage_json=$(aws devops-agent get-account-usage --region "$REGION" --output json 2>&1)
if [[ $? -ne 0 ]]; then
  echo "ERROR: could not read the usage meter." >&2
  echo "$usage_json" | head -3 >&2
  echo >&2
  echo "If this says AccessDenied, the account has no agent space yet -- the usage" >&2
  echo "API only answers once the account has been onboarded. Create one first." >&2
  exit 1
fi

python - "$usage_json" "$RATE_PER_SECOND" <<'PYEOF'
import json
import sys

data = json.loads(sys.argv[1])
rate = float(sys.argv[2])

CATEGORIES = [
    ("monthlyAccountInvestigationHours", "investigations (incident response)"),
    ("monthlyAccountEvaluationHours", "evaluations (incident prevention)"),
    ("monthlyAccountOnDemandHours", "on-demand SRE tasks (chat)"),
    ("monthlyAccountSystemLearningHours", "system learning"),
]

print()
print("  %-38s %10s %12s  %s" % ("category", "hours", "cost", "limit"))
print("  " + "-" * 76)

total_hours = 0.0
for key, label in CATEGORIES:
    entry = data.get(key) or {}
    hours = float(entry.get("usage", 0.0))
    limit = entry.get("limit", -1)
    total_hours += hours
    # limit -1 means no cap. Worth printing rather than hiding: the absence of a
    # ceiling is the point of this script.
    limit_text = "none" if limit in (-1, None) else str(limit)
    print("  %-38s %10.4f %12s  %s"
          % (label, hours, "$%.2f" % (hours * 3600 * rate), limit_text))

print("  " + "-" * 76)
print("  %-38s %10.4f %12s" % ("TOTAL", total_hours, "$%.2f" % (total_hours * 3600 * rate)))
print()
print("  period: %s -> %s" % (data.get("usagePeriodStartTime", "?"),
                              data.get("usagePeriodEndTime", "?")))
print("  rate:   $%s per agent-second ($%.2f per minute)" % (rate, rate * 60))
print()
if total_hours == 0.0:
    print("  Nothing has billed yet.")
PYEOF
