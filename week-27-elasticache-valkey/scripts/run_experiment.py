#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Same request count, three value sizes. Estimate beside measurement.

    python scripts/run_experiment.py [--requests 200000] [--json results.json]

Prints two numbers per size: the ECPUs the byte dimension implies, and the
ECPUs CloudWatch reports as billed. The article's table uses the measured
column -- publishing the estimate would be the mistake the article is about.
"""
from __future__ import annotations

import argparse
import datetime as dt
import io
import json
import subprocess
import sys
import time

import boto3

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SIZES_KB = [1, 10, 100]
ECPU_PRICE_PER_MILLION = 0.0023      # us-east-1, verified 2026-11-10


def tf_output(name):
    out = subprocess.run(["terraform", "output", "-raw", name],
                         cwd="terraform/environments/dev",
                         capture_output=True, text=True)
    if out.returncode:
        sys.exit("terraform output %s failed:\n%s" % (name, out.stderr.strip()))
    return out.stdout.strip()


def billed_ecpus(cw, cache_name, start, end):
    """ElastiCacheProcessingUnits summed over the window, from CloudWatch."""
    r = cw.get_metric_statistics(
        Namespace="AWS/ElastiCache",
        MetricName="ElastiCacheProcessingUnits",
        Dimensions=[{"Name": "clusterId", "Value": cache_name}],
        StartTime=start, EndTime=end, Period=60, Statistics=["Sum"])
    pts = r.get("Datapoints", [])
    return sum(p["Sum"] for p in pts) if pts else None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--requests", type=int, default=200_000)
    ap.add_argument("--json", dest="json_path")
    a = ap.parse_args()

    fn = tf_output("client_function")
    cache = tf_output("cache_name")
    lam, cw = boto3.client("lambda"), boto3.client("cloudwatch")
    rows = []

    for size in SIZES_KB:
        start = dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=1)
        r = lam.invoke(FunctionName=fn, Payload=json.dumps(
            {"size_kb": size, "requests": a.requests}).encode())
        payload = json.loads(r["Payload"].read() or b"{}")
        if "FunctionError" in r:
            sys.exit("invocation failed at %d KB:\n%s" % (size, payload))

        # CloudWatch publishes on a delay; without this the window is empty
        # and the measured column would read as zero rather than as pending.
        print("  %d KB done in %ss, waiting for CloudWatch..."
              % (size, payload["seconds"]))
        time.sleep(180)
        payload["ecpus_billed"] = billed_ecpus(
            cw, cache, start, dt.datetime.now(dt.timezone.utc))
        rows.append(payload)

    print("\n%-8s %11s %15s %15s %12s" %
          ("value", "requests", "ECPUs est.", "ECPUs billed", "cost USD"))
    print("-" * 66)
    for r in rows:
        billed = r["ecpus_billed"]
        cost = ("$%.6f" % (billed / 1e6 * ECPU_PRICE_PER_MILLION)
                if billed is not None else "pending")
        print("%-8s %11s %15s %15s %12s" % (
            "%d KB" % r["size_kb"], "{:,}".format(r["requests"]),
            "{:,}".format(r["ecpus_estimated"]),
            "{:,.0f}".format(billed) if billed is not None else "pending",
            cost))

    measured = [r for r in rows if r["ecpus_billed"]]
    if len(measured) >= 2:
        lo, hi = measured[0], measured[-1]
        print("\nIdentical request counts. The %d KB workload billed %.0fx the "
              "%d KB one."
              % (hi["size_kb"], hi["ecpus_billed"] / lo["ecpus_billed"],
                 lo["size_kb"]))
    else:
        print("\nCloudWatch has not published yet. Re-run the measurement "
              "before quoting any figure.")
    print("Sizing a cache on requests per second reads none of this.")

    if a.json_path:
        io.open(a.json_path, "w", encoding="utf-8").write(json.dumps(rows, indent=2))
        print("wrote %s" % a.json_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
