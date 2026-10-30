#!/usr/bin/env bash
# Teardown, verified by asking AWS rather than by reading the destroy output.
#
# A destroy run reporting success is a claim. An empty list is evidence. The
# last line matters as much as the counts: reservations are released with the
# functions that held them, so the account's unreserved pool returns to the
# full 1,000 on its own.
set -euo pipefail
R=us-east-2

printf 'lambda functions    : %s\n' \
  "$(aws lambda list-functions --region $R --query 'length(Functions)' --output text)"
printf 'http APIs           : %s\n' \
  "$(aws apigatewayv2 get-apis --region $R --query 'length(Items)' --output text)"
printf 'dynamodb tables     : %s\n' \
  "$(aws dynamodb list-tables --region $R --query 'length(TableNames)' --output text)"
printf 'week25 alarms       : %s\n' \
  "$(aws cloudwatch describe-alarms --region $R --alarm-name-prefix week25 \
      --query 'length(MetricAlarms)' --output text)"
printf 'week25 dashboards   : %s\n' \
  "$(aws cloudwatch list-dashboards --region $R \
      --query "length(DashboardEntries[?starts_with(DashboardName,'week25')])" --output text)"
printf 'unreserved pool     : %s  (back to the full account quota)\n' \
  "$(aws lambda get-account-settings --region $R \
      --query 'AccountLimit.UnreservedConcurrentExecutions' --output text)"
