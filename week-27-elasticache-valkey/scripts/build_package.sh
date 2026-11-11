#!/usr/bin/env bash
# Build the Lambda package. valkey-py is not in the Python runtime.
#
# The zip lands in terraform/environments/dev/build because a remote HCP run
# uploads only the root module directory.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
BUILD="$ROOT/terraform/environments/dev/build"

rm -rf "$BUILD"; mkdir -p "$BUILD"
python -m pip install --quiet --disable-pip-version-check --target "$BUILD" "valkey>=6.2.0"
cp "$ROOT/src/cache_client/handler.py" "$BUILD/handler.py"

# pip writes console-script wrappers and RECORD files that embed paths, so the
# package would hash differently on every build.
rm -rf "$BUILD/bin"
find "$BUILD" -name 'RECORD' -path '*.dist-info*' -delete 2>/dev/null || true
find "$BUILD" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true

python - "$BUILD" <<'INNER'
import os, sys
b = sys.argv[1]
for need in ("handler.py", "valkey"):
    if not os.path.exists(os.path.join(b, need)):
        sys.exit("MISSING FROM PACKAGE: %s" % need)
print("    handler.py and valkey present")
INNER
du -sh "$BUILD" | awk '{print "==> package: " $1}'
