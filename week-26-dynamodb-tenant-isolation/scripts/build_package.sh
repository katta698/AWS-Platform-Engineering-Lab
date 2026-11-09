#!/usr/bin/env bash
# Build the Lambda package. amazon-dax-client is not in the Python runtime.
#
# The zip goes into terraform/environments/dev because a remote run uploads
# only the root module directory. Built locally, so the workspace must be
# CLI-driven, not VCS-connected.
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

# pip generates console-script wrappers in bin/. On Windows those are .exe
# files, which are useless in a Linux Lambda and are not even reproducible --
# each one embeds a path, so the package hashes differently on every build and
# Terraform replaces all three functions for no reason. RECORD goes too: it
# stores a hash of every file including those wrappers, and nothing reads it
# at runtime (pip uses it to uninstall).
echo "==> removing pip install metadata that does not belong in a Lambda"
rm -rf "$BUILD/bin"
find "$BUILD" -name 'RECORD' -path '*.dist-info*' -delete 2>/dev/null || true

# The import check above runs the package, which writes __pycache__ into it.
# Those .pyc files embed a timestamp, so leaving them in makes every build
# hash differently and Terraform sees a changed function on every apply.
# They are also dead weight: Lambda compiles on cold start regardless.
echo "==> removing bytecode left by the import check"
find "$BUILD" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true

ZIP="$ROOT/terraform/environments/dev/tenant_api.zip"
echo "==> zipping to ${ZIP#$ROOT/}"
rm -f "$ZIP"

# Written with Python's zipfile rather than the zip(1) binary: this repo is
# driven from Windows as often as not, and zip is not present there.
# Members are stored with forward slashes at the zip root, sorted, and with a
# fixed timestamp so an unchanged package hashes the same twice and Terraform
# does not see a spurious change.
python - "$BUILD" "$ZIP" <<'INNER'
import os, sys, zipfile

build, out = sys.argv[1], sys.argv[2]
paths = []
for root, _dirs, files in os.walk(build):
    for f in files:
        full = os.path.join(root, f)
        paths.append((os.path.relpath(full, build).replace(os.sep, "/"), full))
paths.sort()

with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name, full in paths:
        info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        with open(full, "rb") as fh:
            z.writestr(info, fh.read())

names = zipfile.ZipFile(out).namelist()
for required in ("handler.py", "amazondax/__init__.py"):
    if required not in names:
        sys.exit("ZIP IS MISSING %s" % required)
print("    %d files, handler.py and amazondax present at the zip root" % len(names))
INNER

du -sh "$ZIP" | awk '{print "==> zip size: " $1}'
