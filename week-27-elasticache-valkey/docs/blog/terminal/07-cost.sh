# The settled bill, by usage type. Storage against requests.

aws ce get-cost-and-usage --region us-east-1 \
  --time-period Start=2026-11-13,End=2026-11-15 --granularity MONTHLY \
  --metrics UnblendedCost --group-by Type=DIMENSION,Key=USAGE_TYPE \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon ElastiCache"]}}' \
  --query 'ResultsByTime[0].Groups[].[Keys[0],Metrics.UnblendedCost.Amount]' \
  --output table
