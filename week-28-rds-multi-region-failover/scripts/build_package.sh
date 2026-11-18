#!/usr/bin/env bash
# Build the Lambda package. psycopg2 is not in the Python runtime.
#
# The zip lands in terraform/environments/dev/build because a remote HCP run
# uploads only the root module directory.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
BUILD="$ROOT/terraform/environments/dev/build"

rm -rf "$BUILD"; mkdir -p "$BUILD"

# psycopg2 ships compiled C extensions, so the wheel has to match the Lambda
# runtime rather than this machine. Building on Windows without --platform
# yields a package that imports fine locally and fails in AWS.
python -m pip install --quiet --disable-pip-version-check --target "$BUILD" \
  --platform manylinux2014_x86_64 --only-binary=:all: --python-version 3.13 \
  "psycopg2-binary>=2.9.9"
cp "$ROOT/src/writer/handler.py" "$BUILD/handler.py"

# pip writes console-script wrappers and RECORD files that embed paths, so the
# package would hash differently on every build.
rm -rf "$BUILD/bin"
find "$BUILD" -name 'RECORD' -path '*.dist-info*' -delete 2>/dev/null || true
find "$BUILD" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true

python - "$BUILD" <<'INNER'
import os, sys
b = sys.argv[1]
for need in ("handler.py", "psycopg2"):
    if not os.path.exists(os.path.join(b, need)):
        sys.exit("MISSING FROM PACKAGE: %s" % need)
# A manylinux wheel for the wrong Python would install a .so the runtime
# cannot load. Check one is actually there rather than trusting pip's exit.
so = [f for f in os.listdir(os.path.join(b, "psycopg2")) if f.endswith(".so")]
if not so:
    sys.exit("no compiled extension in psycopg2/ -- wrong wheel platform")
print("    handler.py and psycopg2 present (%s)" % so[0])
INNER
du -sh "$BUILD" | awk '{print "==> package: " $1}'
