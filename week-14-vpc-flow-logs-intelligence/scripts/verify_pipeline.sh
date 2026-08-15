#!/usr/bin/env bash
#
# Week 14 pipeline verification.
#
# Run this after the first apply, once logs have had ~15 minutes to arrive.
#
# It exists because almost every failure mode in this build is SILENT:
#
#   * A partition projection template that does not match the real S3 prefixes
#     returns zero rows and reports SUCCEEDED.
#   * A delivery role missing ec2:DescribeTags produces a column of '-' rather
#     than an error.
#   * A log_format whose field order disagrees with the Glue schema returns
#     values under the wrong column names, all of them plausible.
#
# None of those raise anything. Reading the Terraform back will not find them.
# The only way to catch them is to look at real delivered data, which is what
# this does.

set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
PREFIX="week14-flowlogs"

fail=0
note() { echo; echo "=== $* ==="; }
bad()  { echo "  FAIL: $*"; fail=1; }
ok()   { echo "  ok:   $*"; }

###############################################################################
note "1. Locating the bucket"
###############################################################################

BUCKET=$(aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, '${PREFIX}')].Name | [0]" --output text 2>/dev/null)

if [[ -z "$BUCKET" || "$BUCKET" == "None" ]]; then
  bad "no bucket found with prefix ${PREFIX} -- has the apply run?"
  exit 1
fi
ok "bucket: $BUCKET"

###############################################################################
note "2. Have any logs actually been delivered?"
###############################################################################

# Delivery takes about 10 minutes after the first traffic, and files are written
# in 5-minute batches. An empty result here shortly after apply is expected,
# not broken.
KEYS=$(aws s3 ls "s3://${BUCKET}/AWSLogs/" --recursive 2>&1 | tail -5)

if [[ -z "$KEYS" ]]; then
  bad "no objects under AWSLogs/ yet -- wait ~15 minutes after apply and retry"
else
  ok "objects present. Most recent keys:"
  echo "$KEYS" | sed 's/^/          /'
fi

###############################################################################
note "3. Does the real prefix match what the Glue table projects?"
###############################################################################

# This is the comparison. Not a re-read of the config -- an actual delivered key
# against the actual template.
SAMPLE_KEY=$(aws s3 ls "s3://${BUCKET}/AWSLogs/" --recursive 2>/dev/null | tail -1 | awk '{print $4}')

if [[ -n "$SAMPLE_KEY" ]]; then
  echo "  delivered key:"
  echo "          $SAMPLE_KEY"
  echo
  echo "  expected shape:"
  echo "          AWSLogs/aws-account-id=<acct>/aws-service=vpcflowlogs/aws-region=<region>/year=YYYY/month=MM/day=DD/hour=HH/<file>.parquet"
  echo

  for part in "aws-account-id=" "aws-service=vpcflowlogs" "aws-region=" "year=" "month=" "day=" "hour="; do
    if [[ "$SAMPLE_KEY" == *"$part"* ]]; then
      ok "prefix contains '$part'"
    else
      bad "prefix is MISSING '$part' -- projection template will not resolve, every query will return zero rows"
    fi
  done

  if [[ "$SAMPLE_KEY" == *.parquet ]]; then
    ok "file is Parquet"
  else
    bad "file is not .parquet -- destination_options.file_format did not take effect"
  fi
fi

###############################################################################
note "4. Is the flow log subscription healthy?"
###############################################################################

FLOW_STATUS=$(aws ec2 describe-flow-logs --region "$REGION" \
  --filter "Name=tag:Week,Values=14" \
  --query "FlowLogs[0].[FlowLogStatus,DeliverLogsStatus,DeliverLogsErrorMessage]" \
  --output text 2>&1)

if [[ $? -ne 0 ]]; then
  bad "could not describe flow logs: $FLOW_STATUS"
else
  echo "          status / delivery / error: $FLOW_STATUS"
  if [[ "$FLOW_STATUS" == *"ACTIVE"* ]]; then
    ok "subscription ACTIVE"
  else
    bad "subscription not ACTIVE"
  fi
  # A delivery error here is usually the bucket policy rejecting the write.
  if [[ "$FLOW_STATUS" == *"SUCCESS"* || "$FLOW_STATUS" == *"None"* ]]; then
    ok "no delivery error reported"
  else
    bad "delivery error reported -- check the bucket policy"
  fi
fi

###############################################################################
note "5. Run the sanity query and confirm it returns rows"
###############################################################################

WORKGROUP="${PREFIX}-wg"
DATABASE=$(aws glue get-databases --region "$REGION" \
  --query "DatabaseList[?starts_with(Name, 'week14')].Name | [0]" --output text 2>/dev/null)

if [[ -z "$DATABASE" || "$DATABASE" == "None" ]]; then
  bad "no Glue database found"
else
  ok "database: $DATABASE"

  QUERY="SELECT COUNT(*) AS records, COUNT(DISTINCT instance_tag) AS distinct_tags, MAX(from_unixtime(\"end\")) AS latest FROM \"${DATABASE}\".\"flow_logs\" WHERE concat(year,'-',month,'-',day) >= date_format(current_date - interval '2' day, '%Y-%m-%d')"

  QID=$(aws athena start-query-execution --region "$REGION" \
    --query-string "$QUERY" \
    --work-group "$WORKGROUP" \
    --query "QueryExecutionId" --output text 2>&1)

  if [[ $? -ne 0 ]]; then
    bad "could not start query: $QID"
  else
    echo "          execution: $QID"
    for _ in $(seq 1 30); do
      STATE=$(aws athena get-query-execution --region "$REGION" \
        --query-execution-id "$QID" --query "QueryExecution.Status.State" --output text 2>/dev/null)
      [[ "$STATE" == "SUCCEEDED" || "$STATE" == "FAILED" || "$STATE" == "CANCELLED" ]] && break
      sleep 2
    done

    if [[ "$STATE" != "SUCCEEDED" ]]; then
      REASON=$(aws athena get-query-execution --region "$REGION" \
        --query-execution-id "$QID" --query "QueryExecution.Status.StateChangeReason" --output text 2>/dev/null)
      bad "query ended $STATE: $REASON"
    else
      RESULT=$(aws athena get-query-results --region "$REGION" \
        --query-execution-id "$QID" \
        --query "ResultSet.Rows[1].Data[*].VarCharValue" --output text 2>/dev/null)
      echo "          records / distinct_tags / latest: $RESULT"

      RECORDS=$(echo "$RESULT" | awk '{print $1}')
      TAGS=$(echo "$RESULT" | awk '{print $2}')

      if [[ "$RECORDS" == "0" || -z "$RECORDS" ]]; then
        bad "query succeeded but returned ZERO records."
        echo "                 This is the silent-failure case. Objects exist in S3 but the"
        echo "                 table cannot see them. Compare the delivered key in step 3"
        echo "                 against the partition_location_template output."
      else
        ok "$RECORDS records readable through the table"
      fi

      # If every record's tag is '-', distinct_tags is 1 and the tag fields
      # never resolved -- the delivery role is missing ec2:DescribeTags.
      if [[ "$TAGS" == "1" ]]; then
        echo "  WARN: only one distinct instance_tag value."
        echo "                 If that value is '-', the v11 tag fields are not resolving:"
        echo "                 check ec2:DescribeTags on the flow log delivery role."
      elif [[ -n "$TAGS" ]]; then
        ok "$TAGS distinct instance_tag values -- v11 tag fields are resolving"
      fi
    fi
  fi
fi

###############################################################################
note "6. Has the analyzer published metrics?"
###############################################################################

METRICS=$(aws cloudwatch list-metrics --region "$REGION" \
  --namespace "FlowLogIntelligence" \
  --query "Metrics[].MetricName" --output text 2>&1)

if [[ -z "$METRICS" || "$METRICS" == "None" ]]; then
  echo "  WARN: no metrics in FlowLogIntelligence yet."
  echo "                 The schedule runs hourly. Force a run instead of waiting:"
  echo "                   aws lambda invoke --function-name ${PREFIX}-flow-analyzer out.json && cat out.json"
else
  ok "metrics published: $METRICS"
fi

###############################################################################
echo
if [[ $fail -eq 0 ]]; then
  echo "Pipeline verified end to end."
  exit 0
fi

echo "VERIFICATION FAILED -- see FAIL lines above."
exit 1
