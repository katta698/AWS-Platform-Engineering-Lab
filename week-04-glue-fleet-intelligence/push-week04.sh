#!/usr/bin/env bash
# Run from Git Bash at the repo root:
#   bash week-04-glue-fleet-intelligence/push-week04.sh

set -e
cd "$(git rev-parse --show-toplevel)"

echo "=== What will be committed ==="
git status week-04-glue-fleet-intelligence/
echo ""
read -p "Press Enter to add, commit and push — or Ctrl-C to abort: "

git add week-04-glue-fleet-intelligence/

git commit -m "Week 04: Fleet Intelligence Platform

- Terraform: S3 (raw/curated/athena-results), Glue crawler + ETL job,
  Step Functions state machine, 3 Lambdas, API Gateway, IAM roles
- Glue PySpark ETL: boto3 S3 reader (colon-in-path fix), Parquet output
- Step Functions: Wait->Check->Choice polling loop pattern
- Lambda: webhook_receiver (HMAC-SHA256), glue_trigger, status_updater
- ServiceNow RITM auto-close via REST API PATCH
- Athena workgroup + Glue Data Catalog (Bronze/Silver/Gold medallion)
- GitHub Actions deploy workflow
- Blog screenshots (18 PNGs for Blogger post)"

git push origin main

echo ""
echo "Pushed! https://github.com/katta698/AWS-Platform-Engineering-Lab/tree/main/week-04-glue-fleet-intelligence"
