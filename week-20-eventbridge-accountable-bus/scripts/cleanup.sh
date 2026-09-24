#!/usr/bin/env bash
# Verify Week 20 is gone. Run AFTER the HCP destroy, not instead of it.
#
# THIS WEEK HAS NO HOURLY METER, which changes what teardown is for.
# Weeks 18 and 19 billed $0.17-$0.22/hr from the moment the cluster existed, so
# forgetting them was expensive by the hour. EventBridge bills per event: an
# idle bus costs nothing. What DOES keep charging here is small and quiet:
#
#   archive storage        $0.023/GB/month, forever, until deleted
#   CloudTrail data events billed per event, and the trail stays armed
#   schema discovery       metered above 5M events/month
#   S3 trail bucket        storage, plus whatever the trail already wrote
#
# So the risk is not a big number arriving fast. It is a small number arriving
# indefinitely, on a service nobody thinks of as costing anything.
set -uo pipefail
PROFILE="${AWS_PROFILE:-personal}"
PREFIX="week20"
fail=0

check() {
  local label="$1" result="$2"
  if [[ -z "${result// /}" || "$result" == "[]" || "$result" == "None" ]]; then
    printf '  [gone] %s\n' "$label"
  else
    printf '  [LIVE] %s -> %s\n' "$label" "$result"
    fail=1
  fi
}

aws_() { MSYS_NO_PATHCONV=1 aws --profile "$PROFILE" "$@"; }

echo "Week 20 teardown verification"

check "event buses" "$(aws_ events list-event-buses \
  --query "EventBuses[?starts_with(Name,'${PREFIX}')].Name" --output text)"

# Rules must be checked per-bus. A rule on a deleted bus is gone with it, but a
# rule accidentally created on `default` is not -- and that is exactly what
# happens when event_bus_name is omitted from the rule or the target.
check "rules left on the default bus" "$(aws_ events list-rules \
  --query "Rules[?starts_with(Name,'${PREFIX}')].Name" --output text)"

# An archive is NOT deleted by deleting the bus, and its storage keeps billing.
check "archives" "$(aws_ events list-archives \
  --query "Archives[?starts_with(ArchiveName,'${PREFIX}')].ArchiveName" --output text)"

# A replay is a separate resource from the archive it came from.
check "replays" "$(aws_ events list-replays \
  --query "Replays[?starts_with(ReplayName,'${PREFIX}')].ReplayName" --output text)"

# The discoverer meters against the 5M/month free tier while it exists.
check "schema discoverers" "$(aws_ schemas list-discoverers \
  --query "Discoverers[?contains(SourceArn,'${PREFIX}')].DiscovererId" --output text)"

# Discovered schemas live in the AWS-managed `discovered-schemas` registry and
# survive the discoverer. They cost nothing, which is why they accumulate.
check "discovered schemas for this bus" "$(aws_ schemas list-schemas \
  --registry-name discovered-schemas \
  --query "Schemas[?contains(SchemaName,'${PREFIX}')].SchemaName" --output text 2>/dev/null)"

# A trail left armed keeps billing for data events.
check "cloudtrail trails" "$(aws_ cloudtrail list-trails \
  --query "Trails[?starts_with(Name,'${PREFIX}')].Name" --output text)"

check "s3 buckets" "$(aws_ s3api list-buckets \
  --query "Buckets[?starts_with(Name,'${PREFIX}')].Name" --output text)"

check "lambda functions" "$(aws_ lambda list-functions \
  --query "Functions[?starts_with(FunctionName,'${PREFIX}')].FunctionName" --output text)"

check "sqs queues" "$(aws_ sqs list-queues --queue-name-prefix "${PREFIX}" \
  --query "QueueUrls" --output text)"

check "sns topics" "$(aws_ sns list-topics \
  --query "Topics[?contains(TopicArn,'${PREFIX}')].TopicArn" --output text)"

check "iam roles" "$(aws_ iam list-roles \
  --query "Roles[?starts_with(RoleName,'${PREFIX}')].RoleName" --output text)"

check "alarms" "$(aws_ cloudwatch describe-alarms --alarm-name-prefix "${PREFIX}" \
  --query "MetricAlarms[].AlarmName" --output text)"

check "log groups" "$(aws_ logs describe-log-groups \
  --query "logGroups[?contains(logGroupName,'${PREFIX}')].logGroupName" --output text)"

# The catch-all rule needs a log-group RESOURCE POLICY, which is account-level
# and is not attached to any log group Terraform destroys. It costs nothing and
# is invisible in the console's log-group view -- exactly the shape of thing
# that accumulates across weeks.
check "log resource policies" "$(aws_ logs describe-resource-policies \
  --query "resourcePolicies[?contains(policyName,'${PREFIX}')].policyName" --output text)"

echo
if [[ $fail -eq 0 ]]; then
  echo "CLEAN - nothing from Week 20 remains."
else
  echo "NOT CLEAN - see [LIVE] lines above."
  echo "No hourly meter here, but the archive, the trail and the discoverer all"
  echo "keep charging quietly. Small and indefinite beats large and obvious for"
  echo "going unnoticed."
  exit 1
fi
