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
from botocore.config import Config

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

SIZES_KB = [1, 10, 100]
ECPU_PRICE_PER_MILLION = 0.0023      # us-east-1, verified 2026-11-10
QUIET_S = 300                        # idle gap so windows cannot overlap
PUBLISH_S = 420                      # publication delay, incl. the trailing minute


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
    # 20k sequential round-trips fit inside the function's 300s timeout.
    # 200k did not: the invocation ran the full 300,000 ms and errored.
    ap.add_argument("--requests", type=int, default=20_000)
    ap.add_argument("--json", dest="json_path")
    a = ap.parse_args()

    fn = tf_output("client_function")
    cache = tf_output("cache_name")
    # boto3 reads time out at 60s by default, well under the function's
    # 300s timeout, so a synchronous invoke must say so explicitly.
    lam = boto3.client("lambda", config=Config(
        read_timeout=360, connect_timeout=20, retries={"max_attempts": 0}))
    cw = boto3.client("cloudwatch")
    rows = []

    # Each run needs its own quiet window. Overlapping windows, or one that
    # catches a neighbouring run, measure the wrong thing: a first attempt
    # reported 10 KB billing less than 1 KB.
    print("  settling %ds so the first window is quiet..." % QUIET_S)
    time.sleep(QUIET_S)

    for i, size in enumerate(SIZES_KB):
        t0 = dt.datetime.now(dt.timezone.utc)
        r = lam.invoke(FunctionName=fn, Payload=json.dumps(
            {"size_kb": size, "requests": a.requests}).encode())
        payload = json.loads(r["Payload"].read() or b"{}")
        if "FunctionError" in r:
            sys.exit("invocation failed at %d KB:\n%s" % (size, payload))
        t1 = dt.datetime.now(dt.timezone.utc)

        print("  %d KB done in %ss" % (size, payload["seconds"]))
        payload["t0"], payload["t1"] = t0, t1
        rows.append(payload)

        if i < len(SIZES_KB) - 1:
            print("  quiet gap before the next size...")
            time.sleep(QUIET_S)

    # Measure only after every run is finished. A run straddles a minute
    # boundary, and the trailing minute publishes late -- querying straight
    # after each run caught the first minute only and undercounted by 4x.
    print("  waiting %ds for CloudWatch to publish every minute..." % PUBLISH_S)
    time.sleep(PUBLISH_S)
    for payload in rows:
        payload["ecpus_billed"] = billed_ecpus(
            cw, cache,
            payload.pop("t0") - dt.timedelta(seconds=60),
            payload.pop("t1") + dt.timedelta(seconds=120))

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

    # Bytes moved set a floor: a simple GET cannot bill below 1 ECPU per KB.
    # A figure under that floor means the window measured something else.
    impossible = [r for r in rows if r["ecpus_billed"]
                  and r["ecpus_billed"] < r["ecpus_estimated"] * 0.9]
    if impossible:
        print("\nMEASUREMENT REJECTED: billed ECPUs below the byte floor for "
              "%s. This window did not measure this workload. Do not quote "
              "these figures."
              % ", ".join("%d KB" % r["size_kb"] for r in impossible))
        return 1

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
