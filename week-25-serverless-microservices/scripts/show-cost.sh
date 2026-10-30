#!/usr/bin/env bash
# What the week actually cost, read from the bill rather than a rate card.
#
# Filtered to us-east-2 -- the empty region this lab was fenced into. That is
# what the fence is FOR: the region had no API Gateway usage at all the day
# before, so everything below is week 25 and nothing else in the account can
# contaminate the number.
#
# The headline is not the total. It is which service the total landed on.
set -euo pipefail

REGION_ONLY='{"Dimensions":{"Key":"REGION","Values":["us-east-2"]}}'

echo '--- 30 Oct, us-east-2 only: cost by service ---'
aws ce get-cost-and-usage \
  --time-period Start=2026-10-30,End=2026-10-31 \
  --granularity DAILY --metrics UnblendedCost \
  --filter "$REGION_ONLY" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --query 'ResultsByTime[0].Groups[].[Keys[0],Metrics.UnblendedCost.Amount]' \
  --output table

echo '--- the same spend, by usage type: requests, not compute ---'
aws ce get-cost-and-usage \
  --time-period Start=2026-10-30,End=2026-10-31 \
  --granularity DAILY --metrics UnblendedCost UsageQuantity \
  --filter "$REGION_ONLY" \
  --group-by Type=DIMENSION,Key=USAGE_TYPE \
  --query 'ResultsByTime[0].Groups[?Metrics.UnblendedCost.Amount!=`0`].[Keys[0],Metrics.UsageQuantity.Amount,Metrics.UnblendedCost.Amount]' \
  --output table
