#!/bin/bash
# Build Lambda deployment zip packages.
# Run this from the week-04-glue-fleet-intelligence/ directory before terraform apply.
set -euo pipefail

WEEK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "=== Building Lambda zip packages ==="

for fn in webhook_receiver glue_trigger status_updater; do
  echo "  Packaging $fn..."
  cd "$WEEK_DIR/lambda/$fn"
  zip -q "${fn}.zip" handler.py
  echo "  → $fn.zip created ($(wc -c < "${fn}.zip") bytes)"
done

echo ""
echo "=== Done. Ready for terraform apply ==="
echo ""
echo "Next: upload the Glue ETL script after S3 bucket is created:"
echo "  aws s3 cp glue/scripts/fleet_etl.py \\"
echo "    s3://jay-fleet-intelligence-raw-dev/scripts/fleet_etl.py"
