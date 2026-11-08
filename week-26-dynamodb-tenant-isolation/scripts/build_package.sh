#!/usr/bin/env bash
# Build the Lambda package.
#
# The DAX path needs amazon-dax-client, which is not in the Python runtime.
# Without it the "dax" half of every comparison raises ImportError and the
# week has nothing to show, so this runs before every apply.
#
# The package is built locally and uploaded with the configuration, which
# means the week-26-dev workspace must be CLI-driven rather than
# VCS-connected: a VCS run has only what is committed, and build/ is not.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
BUILD="$ROOT/build/package"

echo "==> clearing $BUILD"
rm -rf "$ROOT/build"
mkdir -p "$BUILD"

echo "==> installing amazon-dax-client for the Lambda runtime"
# --platform/--only-binary are not used: amazon-dax-client and its antlr
# dependency are pure Python, so the wheels are not platform specific.
# --target installs flat, which is the layout Lambda expects at the zip root.
python -m pip install \
  --quiet --disable-pip-version-check \
  --target "$BUILD" \
  "amazon-dax-client>=2.1.0"

echo "==> adding handler"
cp "$ROOT/src/tenant_api/handler.py" "$BUILD/handler.py"

# boto3 ships in the runtime; shipping a second copy only makes the zip
# bigger and the versions ambiguous.
rm -rf "$BUILD"/boto3* "$BUILD"/botocore* 2>/dev/null || true

echo "==> verifying the package imports what it claims to"
python - "$BUILD" <<'PY'
import os, sys
build = sys.argv[1]
missing = [n for n in ("handler.py", "amazondax") if not os.path.exists(os.path.join(build, n))]
if missing:
    sys.exit("MISSING FROM PACKAGE: %s" % ", ".join(missing))
sys.path.insert(0, build)
import amazondax                                     # noqa: F401
print("    amazondax %s" % getattr(amazondax, "__version__", "(no __version__)"))
print("    package ok")
PY

du -sh "$BUILD" | awk '{print "==> package size: " $1}'
