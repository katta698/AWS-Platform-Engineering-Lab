#!/usr/bin/env bash
#
# Week 14 teardown verification.
#
# The workspace week-14-dev is VCS-connected. That blocks `terraform destroy`
# from a CLI checkout, but it does NOT block a destroy run queued through HCP --
# either from the UI (Workspace -> Settings -> Destruction and Deletion -> Queue
# destroy plan) or through the API with is-destroy: true on POST /runs.
#
# This script does not destroy anything. It verifies a destroy actually finished
# and reports what survived.
#
# What tends to linger on this build, and why:
#
#   NAT gateway     the expensive one. $0.045/hr with no usage signal to remind
#                   you it exists. Deletion takes a couple of minutes and the
#                   Elastic IP is billed separately until released.
#   Elastic IP      an unattached EIP is billed hourly. It survives the NAT
#                   gateway it was attached to.
#   S3 bucket       force_destroy is set, but a bucket that failed to empty
#                   leaves a real storage charge behind.
#   Anomaly alarms  $3.00/month each. Cheap to forget, not free to forget.

set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
PREFIX="week14-flowlogs"

echo "Checking for surviving Week 14 resources in ${REGION}..."
echo

fail=0

# Three outcomes, not two. An empty result and a failed call look identical if
# you only test for emptiness -- which is how an expired SSO session reports a
# clean teardown while having verified nothing.
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

echo "--- Billed hourly whether used or not ---"

check "NAT gateways" \
  aws ec2 describe-nat-gateways --region "$REGION" \
  --filter "Name=tag:Week,Values=14" "Name=state,Values=available,pending" \
  --query "NatGateways[].NatGatewayId" --output text

check "Elastic IPs" \
  aws ec2 describe-addresses --region "$REGION" \
  --filters "Name=tag:Week,Values=14" \
  --query "Addresses[].AllocationId" --output text

check "EC2 instances" \
  aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Week,Values=14" "Name=instance-state-name,Values=running,pending,stopping,stopped" \
  --query "Reservations[].Instances[].InstanceId" --output text

echo
echo "--- Network ---"

check "VPCs" \
  aws ec2 describe-vpcs --region "$REGION" \
  --filters "Name=tag:Week,Values=14" \
  --query "Vpcs[].VpcId" --output text

check "VPC endpoints" \
  aws ec2 describe-vpc-endpoints --region "$REGION" \
  --filters "Name=tag:Week,Values=14" \
  --query "VpcEndpoints[].VpcEndpointId" --output text

check "Flow log subscriptions" \
  aws ec2 describe-flow-logs --region "$REGION" \
  --filter "Name=tag:Week,Values=14" \
  --query "FlowLogs[].FlowLogId" --output text

check "Security groups" \
  aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=tag:Week,Values=14" \
  --query "SecurityGroups[].GroupId" --output text

echo
echo "--- Storage and analytics ---"

check "S3 buckets" \
  aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, '${PREFIX}')].Name" --output text

check "Glue databases" \
  aws glue get-databases --region "$REGION" \
  --query "DatabaseList[?starts_with(Name, 'week14')].Name" --output text

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

# Anomaly detectors are a separate API from alarms and survive alarm deletion.
# Left behind they are harmless but they clutter the console and confuse a
# later rebuild, which starts reusing a stale trained band.
check "Anomaly detectors" \
  aws cloudwatch describe-anomaly-detectors --region "$REGION" \
  --namespace "FlowLogIntelligence" \
  --query "AnomalyDetectors[].MetricName" --output text

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
  exit 0
fi

echo "TEARDOWN INCOMPLETE -- see STILL PRESENT / ERROR lines above."
echo
echo "ERROR lines mean the check could not run (expired credentials, missing"
echo "permission, wrong region). That is not the same as a clean teardown and"
echo "must not be read as one."
exit 1
