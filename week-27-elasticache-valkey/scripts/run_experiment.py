#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Same request count, three value sizes. Measure what each costs.

    python scripts/run_experiment.py [--requests 200000] [--json results.json]

The estimate everyone makes is requests x price. This prints that beside the
ECPUs actually consumed, which are billed on bytes moved, not requests.
"""
from __future__ import annotations

import argparse
import io
import json
import subprocess
import sys

import boto3

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SIZES_KB = [1, 10, 100]
ECPU_PRICE = 0.0023 / 1_000_000      # us-east-1, verified 2026-11-10


def tf_output(name):
    out = subprocess.run(["terraform", "output", "-raw", name],
                         cwd="terraform/environments/dev",
                         capture_output=True, text=True)
    if out.returncode:
        sys.exit("terraform output %s failed:\n%s" % (name, out.stderr.strip()))
    return out.stdout.strip()


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--requests", type=int, default=200_000)
    ap.add_argument("--json", dest="json_path")
    a = ap.parse_args()

    fn = tf_output("client_function")
    lam = boto3.client("lambda")
    rows = []

    for size in SIZES_KB:
        r = lam.invoke(FunctionName=fn, Payload=json.dumps(
            {"size_kb": size, "requests": a.requests}).encode())
        payload = json.loads(r["Payload"].read() or b"{}")
        if "FunctionError" in r:
            sys.exit("invocation failed for %d KB:\n%s" % (size, payload))
        rows.append(payload)

    print("\n%-10s %12s %14s %14s %12s" %
          ("value", "requests", "KB moved", "ECPUs", "cost USD"))
    print("-" * 66)
    for r in rows:
        print("%-10s %12s %14s %14s %12s" % (
            "%d KB" % r["size_kb"], "{:,}".format(r["requests"]),
            "{:,}".format(r["kb_moved"]), "{:,}".format(r["ecpus_from_bytes"]),
            "$%.6f" % r["cost_usd"]))

    base, worst = rows[0], rows[-1]
    ratio = worst["cost_usd"] / base["cost_usd"] if base["cost_usd"] else 0
    print("\nIdentical request counts. The %d KB workload costs %.0fx the "
          "%d KB one." % (worst["size_kb"], ratio, base["size_kb"]))
    print("Sizing a cache on requests per second reads none of this.")

    if a.json_path:
        io.open(a.json_path, "w", encoding="utf-8").write(json.dumps(rows, indent=2))
        print("wrote %s" % a.json_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
