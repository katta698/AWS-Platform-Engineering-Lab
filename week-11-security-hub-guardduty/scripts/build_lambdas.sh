#!/usr/bin/env bash
# Package each Lambda handler into <name>/<name>.zip.
# HCP VCS-driven runs cannot build artifacts, so the zips are committed
# (git add -f, past the lambda/**/*.zip gitignore rule). Re-run after editing
# any handler.py, then commit the refreshed zip.
#
# Uses Python's zipfile (portable — no `zip` binary needed on Windows/Git Bash).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAMBDA_DIR="$ROOT/lambda"

for fn in sg_remediator s3_remediator threat_notifier; do
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
echo "Done. Commit with: git add -f week-11-security-hub-guardduty/lambda/**/*.zip"
