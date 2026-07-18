#!/bin/bash
set -euo pipefail

echo "=== Week 10 — Centralised Logging Platform: Cleanup ==="
echo ""
echo "This workspace (week-10-dev) is VCS-connected — destroy runs in HCP, not"
echo "from local terraform CLI:"
echo ""
echo "  1. HCP UI -> Katta org -> week-10-dev -> Settings -> Destruction and Deletion"
echo "  2. Queue destroy plan, review, confirm."
echo ""
echo "After destroy, verify nothing is still billing:"
echo "  - CloudWatch log groups under /platform-lab/week10 (both accounts)"
echo "  - The OAM sink/link pair (Console -> CloudWatch -> Settings)"
echo "  - The centralization rule (Console -> CloudWatch -> Logs -> Centralization)"
echo ""
echo "Destroyed cost: \$0."
