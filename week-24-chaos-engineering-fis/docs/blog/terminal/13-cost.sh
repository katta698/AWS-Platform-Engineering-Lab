aws ce get-cost-and-usage --granularity DAILY --metrics UnblendedCost \
  --time-period Start=2026-10-24,End=2026-10-25 \
  --group-by Type=DIMENSION,Key=USAGE_TYPE --filter file://cost-filter.json \
  --query "ResultsByTime[0].Groups[?Metrics.UnblendedCost.Amount!='0'].[Keys[0],Metrics.UnblendedCost.Amount]" \
  --output table
