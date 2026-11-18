#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Print the recorded failover measurement.

    python scripts/show_failover.py

Separate from run_failover.py so the figure can be taken without re-running a
promotion that cannot be undone.
"""
import io
import json
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
path = os.path.join(os.path.dirname(HERE), "results", "failover.json")
d = json.load(io.open(path, encoding="utf-8"))

print("%-26s %s" % ("rows written under load", "{:,}".format(d["rows_written"])))
print("%-26s %.1f s  (average %.1f s)" % (
    "replication lag, peak", d["replica_lag_peak_s"],
    sum(p["avg"] for p in d["replica_lag_points"]) / len(d["replica_lag_points"])))
print("%-26s %.0f s  (%.1f minutes)" % (
    "failover, ARC plan", d["promotion_seconds"], d["promotion_seconds"] / 60))
print("%-26s %.0f s" % ("failover, database only", d["db_promoted_seconds"]))
print("%-26s %s" % ("endpoint unchanged", d["endpoint_unchanged"]))
print("%-26s %s" % ("still replicating after", d["replicating_after"]))
print()
print("A documented RTO is a guess until someone runs it.")
