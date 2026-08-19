#!/usr/bin/env bash
#
# Week 15 teardown verification.
#
# The workspace week-15-dev is VCS-connected. That blocks `terraform destroy`
# from a CLI checkout, but NOT a destroy queued through HCP -- either from the UI
# (Workspace -> Settings -> Destruction and Deletion -> Queue destroy plan) or
# through the API with is-destroy: true on POST /runs.
#
# This script does not destroy anything. It verifies a destroy actually finished
# and reports what survived.
#
# What is specific to this week:
#
#   The ORGANIZATION TRAIL is the one that matters. A trail left behind keeps
#   writing every management event from every account in the organization into a
#   bucket, indefinitely. Delivery of the first copy is free, so there is no
#   sharp cost signal to make you notice -- just a bucket that grows and, once
#   the lifecycle rule is gone with the rest of the stack, never stops.
#
#   TRUSTED ACCESS is deliberately NOT checked as leftover state. It is an
#   organization-level setting, it was a documented manual prerequisite, and
#   other services may rely on it. Removing it is a separate decision, not part
#   of tearing down this week.

set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
PREFIX="week15-audit"

echo "Checking for surviving Week 15 resources in ${REGION}..."
echo

fail=0

# Three outcomes, not two. An empty result and a failed call look identical if
# you only test for emptiness -- which is how an expired session reports a clean
# teardown while having verified nothing.
check() {
  local label="$1"
  shift
  local out rc
  out=$("$@" 2>&1); rc=$?

  if [[ $rc -ne 0 ]]; then
    echo "  ERROR          $label -- could not verify"
    echo "$out" | head -2 | sed 's/^/                 /'
    fail=1
  elif [[ -n "$out" && "$out" != "None" ]]; then
    echo "  STILL PRESENT  $label"
    echo "$out" | sed 's/^/                 /'
    fail=1
  else
    echo "  gone           $label"
  fi
}

echo "--- The one that keeps collecting data if left behind ---"

check "CloudTrail trails" \
  aws cloudtrail list-trails --region "$REGION" \
  --query "Trails[?starts_with(Name, '${PREFIX}')].Name" --output text

echo
echo "--- Storage and analytics ---"

check "S3 buckets" \
  aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, '${PREFIX}')].Name" --output text

check "Glue databases" \
  aws glue get-databases --region "$REGION" \
  --query "DatabaseList[?starts_with(Name, 'week15')].Name" --output text

check "Athena workgroups" \
  aws athena list-work-groups --region "$REGION" \
  --query "WorkGroups[?starts_with(Name, '${PREFIX}')].Name" --output text

echo
echo "--- Compute and alerting ---"

check "Lambda functions" \
  aws lambda list-functions --region "$REGION" \
  --query "Functions[?starts_with(FunctionName, '${PREFIX}')].FunctionName" --output text

check "EventBridge rules" \
  aws events list-rules --region "$REGION" \
  --name-prefix "${PREFIX}" --query "Rules[].Name" --output text

check "CloudWatch alarms" \
  aws cloudwatch describe-alarms --region "$REGION" \
  --alarm-name-prefix "${PREFIX}" --query "MetricAlarms[].AlarmName" --output text

# Every alarm this week is a static threshold, so there should be no anomaly
# detectors at all. Checked anyway: Week 14 proved they are a separate API that
# survives alarm deletion, and a future edit adding an anomaly alarm here would
# otherwise reintroduce that gap silently.
check "Anomaly detectors" \
  aws cloudwatch describe-anomaly-detectors --region "$REGION" \
  --namespace "CloudTrailAudit" \
  --query "AnomalyDetectors[].SingleMetricAnomalyDetector.MetricName" --output text

check "SQS queues" \
  aws sqs list-queues --region "$REGION" \
  --queue-name-prefix "${PREFIX}" --query "QueueUrls" --output text

check "SNS topics" \
  aws sns list-topics --region "$REGION" \
  --query "Topics[?contains(TopicArn, '${PREFIX}')].TopicArn" --output text

check "IAM roles" \
  aws iam list-roles \
  --query "Roles[?starts_with(RoleName, '${PREFIX}')].RoleName" --output text

echo
if [[ $fail -eq 0 ]]; then
  echo "All clear -- every check ran and found nothing."
  echo
  echo "Note: trusted access for cloudtrail.amazonaws.com is left enabled by design."
  echo "It is an organization-level setting and was a manual prerequisite; removing it"
  echo "is a separate decision from tearing down this week."
  exit 0
fi

echo "TEARDOWN INCOMPLETE -- see STILL PRESENT / ERROR lines above."
echo
echo "ERROR lines mean the check could not run (expired credentials, missing"
echo "permission, wrong region). That is not the same as a clean teardown and"
echo "must not be read as one."
exit 1
