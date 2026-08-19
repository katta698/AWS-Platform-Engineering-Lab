#!/usr/bin/env bash
#
# Week 15 pipeline verification.
#
# Run after the first apply, once events have had ~20 minutes to arrive.
#
# It exists because every failure mode in this build is SILENT:
#
#   * A projection template that does not match the delivered prefixes returns
#     zero rows and reports SUCCEEDED. The org-trail layout has five projected
#     keys and more ways to be subtly wrong than the single-account layout AWS
#     documents.
#   * An account missing from the projection enum has its events sitting in S3,
#     intact, and invisible to every query.
#   * A region missing from the enum does the same, which quietly makes the
#     "activity in an unused region" question unanswerable.
#   * A bucket policy granting only the account prefix rather than the org
#     prefix lets the trail create successfully and silently denies every
#     member-account delivery.
#
# None of these raise anything, and none are findable by re-reading the
# Terraform. The only real check is querying delivered data.

set -uo pipefail

REGION="${AWS_REGION:-us-east-1}"
PREFIX="week15-audit"

fail=0
note() { echo; echo "=== $* ==="; }
bad()  { echo "  FAIL: $*"; fail=1; }
ok()   { echo "  ok:   $*"; }
warn() { echo "  WARN: $*"; }

###############################################################################
note "1. Locating the bucket and trail"
###############################################################################

BUCKET=$(aws s3api list-buckets \
  --query "Buckets[?starts_with(Name, '${PREFIX}')].Name | [0]" --output text 2>/dev/null)

if [[ -z "$BUCKET" || "$BUCKET" == "None" ]]; then
  bad "no bucket found with prefix ${PREFIX} -- has the apply run?"
  exit 1
fi
ok "bucket: $BUCKET"

TRAIL="${PREFIX}-org-trail"
TRAIL_INFO=$(aws cloudtrail get-trail --name "$TRAIL" \
  --query "Trail.[IsOrganizationTrail,IsMultiRegionTrail,LogFileValidationEnabled,HomeRegion]" \
  --output text 2>&1)

if [[ $? -ne 0 ]]; then
  bad "could not read trail $TRAIL: $TRAIL_INFO"
else
  echo "          org / multi-region / validation / home: $TRAIL_INFO"
  [[ "$TRAIL_INFO" == *"True"* ]] && ok "trail exists" || bad "trail flags unexpected"
fi

###############################################################################
note "2. Is the trail actually logging?"
###############################################################################

STATUS=$(aws cloudtrail get-trail-status --name "$TRAIL" \
  --query "[IsLogging,LatestDeliveryTime,LatestDeliveryError]" --output text 2>&1)

if [[ $? -ne 0 ]]; then
  bad "could not read trail status: $STATUS"
else
  echo "          logging / last delivery / error: $STATUS"
  if [[ "$STATUS" == True* ]]; then
    ok "IsLogging = True"
  else
    bad "trail is not logging"
  fi
  # A delivery error here is almost always the bucket policy, not IAM.
  if [[ "$STATUS" == *"AccessDenied"* || "$STATUS" == *"InsufficientS3BucketPolicy"* ]]; then
    bad "delivery error present -- check the bucket policy grants the ORG prefix"
  fi
fi

###############################################################################
note "3. Have events been delivered, and under the org prefix?"
###############################################################################

# Delivery takes roughly 5-15 minutes with occasional longer tails. An empty
# result shortly after apply is expected, not broken.
KEYS=$(aws s3 ls "s3://${BUCKET}/AWSLogs/" --recursive 2>/dev/null | grep -v '/$' | tail -5)

if [[ -z "$KEYS" ]]; then
  bad "no objects under AWSLogs/ yet -- wait ~20 minutes after apply and retry"
else
  ok "objects present. Most recent:"
  echo "$KEYS" | sed 's/^/          /'
fi

SAMPLE_KEY=$(aws s3 ls "s3://${BUCKET}/AWSLogs/" --recursive 2>/dev/null | grep -v '/$' | tail -1 | awk '{print $4}')

if [[ -n "$SAMPLE_KEY" ]]; then
  echo
  echo "  delivered key:"
  echo "          $SAMPLE_KEY"
  echo "  expected shape (ORGANIZATION trail):"
  echo "          AWSLogs/<org-id>/<account-id>/CloudTrail/<region>/YYYY/MM/DD/<file>.json.gz"
  echo

  # The org-id segment is the whole difference from a single-account trail. If it
  # is absent, this is not an org trail and the Athena table location is wrong.
  if [[ "$SAMPLE_KEY" =~ AWSLogs/o-[a-z0-9]+/ ]]; then
    ok "prefix contains an organization ID segment"
  else
    bad "prefix has NO org-id segment -- this is a single-account layout, and the table location will not match"
  fi

  for part in "/CloudTrail/" ; do
    [[ "$SAMPLE_KEY" == *"$part"* ]] && ok "prefix contains '$part'" \
      || bad "prefix MISSING '$part' -- projection template will not resolve"
  done
fi

###############################################################################
note "4. Which accounts have actually delivered?"
###############################################################################

# This is the check for the projection enum. An account delivering to S3 but
# absent from the enum is invisible to every query, with no error anywhere.
DELIVERED=$(aws s3 ls "s3://${BUCKET}/AWSLogs/" --recursive 2>/dev/null \
  | grep -oE 'AWSLogs/o-[a-z0-9]+/[0-9]{12}/' | grep -oE '[0-9]{12}' | sort -u)

if [[ -z "$DELIVERED" ]]; then
  warn "no per-account prefixes yet (only the management account may have activity so far)"
else
  echo "  accounts delivering:"
  echo "$DELIVERED" | sed 's/^/          /'
fi

###############################################################################
note "5. Run the sanity query -- it must return rows"
###############################################################################

WORKGROUP="${PREFIX}-wg"
DATABASE=$(aws glue get-databases --region "$REGION" \
  --query "DatabaseList[?starts_with(Name, 'week15')].Name | [0]" --output text 2>/dev/null)

if [[ -z "$DATABASE" || "$DATABASE" == "None" ]]; then
  bad "no Glue database found"
else
  ok "database: $DATABASE"

  QUERY="SELECT count(*) AS events, count(distinct account) AS accounts, count(distinct region) AS regions, max(eventtime) AS latest FROM \"${DATABASE}\".\"cloudtrail_events\" WHERE year = date_format(current_date,'%Y') AND month = date_format(current_date,'%m')"

  QID=$(aws athena start-query-execution --region "$REGION" \
    --query-string "$QUERY" --work-group "$WORKGROUP" \
    --query "QueryExecutionId" --output text 2>&1)

  if [[ $? -ne 0 ]]; then
    bad "could not start query: $QID"
  else
    echo "          execution: $QID"
    for _ in $(seq 1 40); do
      STATE=$(aws athena get-query-execution --region "$REGION" \
        --query-execution-id "$QID" --query "QueryExecution.Status.State" --output text 2>/dev/null)
      [[ "$STATE" == "SUCCEEDED" || "$STATE" == "FAILED" || "$STATE" == "CANCELLED" ]] && break
      sleep 3
    done

    if [[ "$STATE" != "SUCCEEDED" ]]; then
      REASON=$(aws athena get-query-execution --region "$REGION" \
        --query-execution-id "$QID" --query "QueryExecution.Status.StateChangeReason" --output text 2>/dev/null)
      bad "query ended $STATE: $REASON"
    else
      RESULT=$(aws athena get-query-results --region "$REGION" \
        --query-execution-id "$QID" \
        --query "ResultSet.Rows[1].Data[*].VarCharValue" --output text 2>/dev/null)
      echo "          events / accounts / regions / latest: $RESULT"

      EVENTS=$(echo "$RESULT" | awk '{print $1}')
      ACCOUNTS=$(echo "$RESULT" | awk '{print $2}')

      if [[ "$EVENTS" == "0" || -z "$EVENTS" ]]; then
        bad "query succeeded but returned ZERO events."
        echo "                 This is the silent-failure case. Objects exist in S3 but the"
        echo "                 table cannot see them. Compare a delivered key from step 3"
        echo "                 against: terraform output partition_location_template"
      else
        ok "$EVENTS events readable through the table"
      fi

      # Cross-check the enum against reality.
      if [[ -n "$DELIVERED" && -n "$ACCOUNTS" ]]; then
        DELIVERED_COUNT=$(echo "$DELIVERED" | wc -l | tr -d ' ')
        if [[ "$ACCOUNTS" -lt "$DELIVERED_COUNT" ]]; then
          bad "$DELIVERED_COUNT account(s) delivering to S3 but only $ACCOUNTS visible in the table"
          echo "                 An account is missing from the projection enum. Check:"
          echo "                   terraform output projected_accounts"
        else
          ok "all delivering accounts are visible through the table"
        fi
      fi
    fi
  fi
fi

###############################################################################
note "6. Has the analyzer published metrics?"
###############################################################################

METRICS=$(aws cloudwatch list-metrics --region "$REGION" \
  --namespace "CloudTrailAudit" --query "Metrics[].MetricName" --output text 2>&1)

if [[ -z "$METRICS" || "$METRICS" == "None" ]]; then
  warn "no metrics in CloudTrailAudit yet. The schedule is DAILY; force a run:"
  echo "                   aws lambda invoke --function-name ${PREFIX}-audit-analyzer out.json && cat out.json"
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
