#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Measure replication lag, then time the failover. One run only.

    python scripts/run_failover.py [--rows 20000] [--json results/failover.json]

Promotion is irreversible, so this script gets one attempt per deploy. It
refuses to start unless replication is confirmed live, and it reads the lag
from CloudWatch rather than inferring it, because an unmeasured lag is the
thing the article is about.
"""
from __future__ import annotations

import argparse
import datetime as dt
import io
import json
import os
import subprocess
import sys
import time

import boto3
from botocore.config import Config

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PRIMARY = "us-east-1"
REPLICA = "us-west-2"
PUBLISH_S = 180   # CloudWatch needs the trailing minute to publish


def tf_output(name):
    out = subprocess.run(["terraform", "output", "-raw", name],
                         cwd="terraform/environments/dev",
                         capture_output=True, text=True)
    if out.returncode:
        sys.exit("terraform output %s failed:\n%s" % (name, out.stderr.strip()))
    return out.stdout.strip()


def replica_state(rds, identifier):
    d = rds.describe_db_instances(DBInstanceIdentifier=identifier)
    i = d["DBInstances"][0]
    return {
        "status": i["DBInstanceStatus"],
        "source": i.get("ReadReplicaSourceDBInstanceIdentifier")
                  or i.get("ReadReplicaSourceDBClusterIdentifier"),
        "endpoint": i["Endpoint"]["Address"],
    }


def lag_datapoints(cw, identifier, start, end):
    r = cw.get_metric_statistics(
        Namespace="AWS/RDS", MetricName="ReplicaLag",
        Dimensions=[{"Name": "DBInstanceIdentifier", "Value": identifier}],
        StartTime=start, EndTime=end, Period=60,
        Statistics=["Average", "Maximum"])
    return sorted(r.get("Datapoints", []), key=lambda p: p["Timestamp"])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--rows", type=int, default=20_000)
    ap.add_argument("--json", dest="json_path", default="results/failover.json")
    a = ap.parse_args()

    primary_id = tf_output("primary_identifier")
    replica_id = tf_output("replica_identifier")
    fn = tf_output("writer_function")

    rds_r = boto3.client("rds", region_name=REPLICA)
    cw_r = boto3.client("cloudwatch", region_name=REPLICA)
    # A synchronous invoke must outlast the function's own 300s timeout;
    # boto3's default read timeout is 60s.
    lam = boto3.client("lambda", region_name=PRIMARY, config=Config(
        read_timeout=360, connect_timeout=20, retries={"max_attempts": 0}))

    before = replica_state(rds_r, replica_id)
    print("replica %s: %s, replicating from %s"
          % (replica_id, before["status"], before["source"]))
    if not before["source"]:
        return fail("this instance is not a replica. It may already have been "
                    "promoted -- promotion cannot be undone, so re-deploy "
                    "before measuring.")
    if before["status"] != "available":
        return fail("replica status is %r, not available." % before["status"])

    # ── Write load ─────────────────────────────────────────────────────────
    t0 = dt.datetime.now(dt.timezone.utc)
    print("\nwriting %s rows to the primary..." % "{:,}".format(a.rows))
    resp = lam.invoke(FunctionName=fn,
                      Payload=json.dumps({"rows": a.rows}).encode())
    payload = json.loads(resp["Payload"].read() or b"{}")
    if "FunctionError" in resp:
        return fail("the writer failed:\n%s" % json.dumps(payload, indent=2))
    print("  %s rows in %ss" % ("{:,}".format(payload["rows_in_table"]),
                                payload["seconds"]))
    t1 = dt.datetime.now(dt.timezone.utc)

    print("  waiting %ds for CloudWatch to publish the lag window..." % PUBLISH_S)
    time.sleep(PUBLISH_S)
    pts = lag_datapoints(cw_r, replica_id,
                         t0 - dt.timedelta(minutes=1),
                         t1 + dt.timedelta(minutes=2))
    if not pts:
        return fail("no ReplicaLag datapoints in the write window. Measuring "
                    "the failover without the lag would publish half the "
                    "finding.")
    peak = max(p["Maximum"] for p in pts)
    print("\nReplicaLag across the write window: peak %.0fs over %d minute(s)"
          % (peak, len(pts)))
    print("  that peak is the data-loss window if the region had failed then.")

    # ── Failover. Irreversible from here. ──────────────────────────────────
    print("\npromoting %s. This cannot be undone." % replica_id)
    promote_started = time.time()
    rds_r.promote_read_replica(DBInstanceIdentifier=replica_id)

    # "available" alone is not the answer: the instance reports available
    # while still a replica for a few seconds. Wait for the source link to
    # disappear, which is what promotion actually changes.
    deadline = promote_started + 900
    promoted_at = None
    while time.time() < deadline:
        s = replica_state(rds_r, replica_id)
        if s["source"] is None and s["status"] == "available":
            promoted_at = time.time()
            break
        time.sleep(10)
    if promoted_at is None:
        return fail("the replica did not finish promoting within 15 minutes.")

    elapsed = promoted_at - promote_started
    after = replica_state(rds_r, replica_id)

    print("\npromoted in %.0fs (%.1f minutes)." % (elapsed, elapsed / 60))
    print("  endpoint unchanged: %s" % (after["endpoint"] == before["endpoint"]))
    print("  still replicating:  %s" % (after["source"] is not None))

    if after["source"] is not None:
        return fail("the instance still reports a replication source after "
                    "promotion. Do not quote this timing.")

    rows = {
        "primary": primary_id,
        "replica": replica_id,
        "rows_written": payload["rows_in_table"],
        "write_seconds": payload["seconds"],
        "replica_lag_peak_s": peak,
        "replica_lag_points": [
            {"t": p["Timestamp"].isoformat(), "avg": p["Average"],
             "max": p["Maximum"]} for p in pts],
        "promotion_seconds": round(elapsed, 1),
        "endpoint_unchanged": after["endpoint"] == before["endpoint"],
        "replicating_after": after["source"] is not None,
        "measured_at": dt.datetime.now(dt.timezone.utc).isoformat(),
    }

    print("\nA documented RTO is a guess until someone runs it. This one took "
          "%.0f seconds." % elapsed)

    os.makedirs(os.path.dirname(a.json_path) or ".", exist_ok=True)
    io.open(a.json_path, "w", encoding="utf-8").write(json.dumps(rows, indent=2))
    print("wrote %s" % a.json_path)
    return 0


def fail(msg):
    print("\nMEASUREMENT REJECTED: %s" % msg)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
