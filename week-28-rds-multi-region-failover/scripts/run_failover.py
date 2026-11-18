#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Measure replication lag, then time the failover through ARC. One run only.

    python scripts/run_failover.py [--rows 400000] [--json results/failover.json]

Promotion is irreversible, so this script gets one attempt per deploy. It
refuses to start unless replication is confirmed live, and it reads the lag
from CloudWatch rather than inferring it, because an unmeasured lag is the
thing the article is about.

The failover runs by executing the Region switch plan, not by calling
rds:PromoteReadReplica. Calling the API directly would measure how fast RDS
promotes, which is not the claim -- the claim is about an orchestrated
runbook, so the orchestrator is what belongs on the clock.
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
LOAD_S = 300      # sustained write window; lag on an idle primary is meaningless


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
    # Rows per invocation, repeated for LOAD_S. 400k measured 18s.
    ap.add_argument("--rows", type=int, default=400_000)
    ap.add_argument("--json", dest="json_path", default="results/failover.json")
    a = ap.parse_args()

    primary_id = tf_output("primary_identifier")
    replica_id = tf_output("replica_identifier")
    fn = tf_output("writer_function")

    rds_r = boto3.client("rds", region_name=REPLICA)
    cw_r = boto3.client("cloudwatch", region_name=REPLICA)
    # An activate flow must be STARTED in the region being activated:
    # "An activate flow should be run on the target region." That is the point
    # of a per-region data plane -- failing over to us-west-2 must not require
    # a call into the region you are evacuating.
    arc = boto3.client("arc-region-switch", region_name=REPLICA)
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
    #
    # Sustained, not a burst. On an IDLE primary, ReplicaLag reports the age
    # of the last WAL record received, so it climbs by 60s every minute while
    # the replica is perfectly caught up, then drops the moment a write lands.
    # Measured here before this was written: 218, 278, 38, 98, 158, 218, 278,
    # 38 -- a sawtooth that looks like minutes of data loss and means the
    # opposite. Lag is only meaningful while writes are flowing.
    t0 = dt.datetime.now(dt.timezone.utc)
    print("\nwriting to the primary for %ds..." % LOAD_S)
    written = 0
    while (dt.datetime.now(dt.timezone.utc) - t0).total_seconds() < LOAD_S:
        resp = lam.invoke(FunctionName=fn,
                          Payload=json.dumps({"rows": a.rows}).encode())
        payload = json.loads(resp["Payload"].read() or b"{}")
        if "FunctionError" in resp:
            return fail("the writer failed:\n%s" % json.dumps(payload, indent=2))
        written = payload["rows_in_table"]
        print("  %s rows total" % "{:,}".format(written))
    t1 = dt.datetime.now(dt.timezone.utc)

    print("  waiting %ds for CloudWatch to publish the lag window..." % PUBLISH_S)
    time.sleep(PUBLISH_S)
    # Only the minutes fully inside the load count. A datapoint from before
    # the first write carries the idle sawtooth, not replication lag.
    pts = [p for p in lag_datapoints(cw_r, replica_id,
                                     t0, t1 + dt.timedelta(minutes=1))
           if t0 <= p["Timestamp"] <= t1]
    if len(pts) < 2:
        return fail("only %d ReplicaLag datapoint(s) inside the write window. "
                    "Measuring the failover without the lag would publish half "
                    "the finding." % len(pts))
    peak = max(p["Maximum"] for p in pts)
    typical = sum(p["Average"] for p in pts) / len(pts)

    # The sawtooth increments by exactly 60 per minute. If what came back is
    # still climbing in step with the clock, the writes were not reaching the
    # primary and this is idleness again, not lag.
    climbing = all(
        abs((b["Average"] - a_["Average"]) - 60) < 5
        for a_, b in zip(pts, pts[1:]))
    if climbing:
        return fail("ReplicaLag rose by 60s per minute across the whole "
                    "window, which is the idle-primary sawtooth rather than "
                    "replication lag. The write load did not land.")

    print("\nReplicaLag under load: peak %.0fs, average %.1fs over %d minute(s)"
          % (peak, typical, len(pts)))
    print("  %s rows written. That peak is the data-loss window if the region "
          "had failed mid-load." % "{:,}".format(written))

    # ── Failover. Irreversible from here. ──────────────────────────────────
    plan_arn = tf_output("plan_arn")
    if not plan_arn:
        return fail("no Region switch plan in the stack. Promoting through "
                    "the RDS API instead would measure RDS, not the runbook.")

    print("\nexecuting the Region switch plan, activating %s." % REPLICA)
    print("  this promotes %s and cannot be undone." % replica_id)
    promote_started = time.time()
    execution = arc.start_plan_execution(
        planArn=plan_arn, targetRegion=REPLICA, action="activate",
        mode="graceful", comment="week 28 measured failover")
    execution_id = execution["executionId"]
    print("  execution %s" % execution_id)

    # Two clocks, answering different questions. ARC reports when its workflow
    # finished; the database is promoted when its replication source
    # disappears, which is what "available" alone does not tell you -- the
    # instance reports available while still a replica for a few seconds.
    deadline = promote_started + 1800
    promoted_at = exec_done_at = None
    last = None
    while time.time() < deadline:
        if exec_done_at is None:
            e = arc.get_plan_execution(planArn=plan_arn,
                                       executionId=execution_id)
            if e["executionState"] != last:
                last = e["executionState"]
                print("  plan execution: %s" % last)
            if last in ("completed", "completedWithExceptions"):
                exec_done_at = time.time()
            elif last in ("failed", "cancelled"):
                return fail("the plan execution ended as %r. The runbook did "
                            "not do what it claims." % last)
        if promoted_at is None:
            st = replica_state(rds_r, replica_id)
            if st["source"] is None and st["status"] == "available":
                promoted_at = time.time()
        if exec_done_at and promoted_at:
            break
        time.sleep(10)
    if promoted_at is None:
        return fail("the replica did not finish promoting within 30 minutes.")

    elapsed = (exec_done_at or promoted_at) - promote_started
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
        "db_promoted_seconds": round(promoted_at - promote_started, 1),
        "execution_id": execution_id,
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
