#!/usr/bin/env bash
# Package the reporter Lambda handler into compliance_reporter/compliance_reporter.zip.
# HCP VCS-driven runs cannot build artifacts, so the zip is committed
# (git add -f, past the lambda/**/*.zip gitignore rule). Re-run after editing
# handler.py, then commit the refreshed zip.
#
# Uses Python's zipfile (portable — no `zip` binary needed on Windows/Git Bash).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAMBDA_DIR="$ROOT/lambda"

for fn in compliance_reporter; do
  src="$LAMBDA_DIR/$fn"
  python - "$src" "$fn" <<'PY'
import sys, zipfile, os
src, fn = sys.argv[1], sys.argv[2]
zip_path = os.path.join(src, fn + ".zip")
if os.path.exists(zip_path):
    os.remove(zip_path)
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
    z.write(os.path.join(src, "handler.py"), "handler.py")
print("built", zip_path)
PY
done
echo "Done. Commit with: git add -f week-12-config-compliance-automation/lambda/**/*.zip"
