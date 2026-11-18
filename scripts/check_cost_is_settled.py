#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""A cost figure read before its day closed is not the cost.

    python scripts/check_cost_is_settled.py week-28-rds-multi-region-failover
    python scripts/check_cost_is_settled.py --self-test

Cost Explorer reports the current day as partial and keeps revising it. A
figure taken the same day reads low -- week 27 published $0.078 and settled at
$0.1435, 84% higher. This refuses a cost claim dated less than a full day ago,
and one carrying no date at all.

Either form counts, in the week's README:

    Measured, settled 2026-11-19: $0.1435.
    <!-- COST_MEASURED_ON: 2026-11-19 -->
"""
from __future__ import annotations

import argparse
import datetime as dt
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# Two accepted forms. The prose one is already the house style -- "Measured,
# settled 2026-11-14: $0.1435" -- so requiring a separate marker beside a date
# the README already carries would be ceremony, and ceremony gets skipped.
STAMP = re.compile(
    r"COST_MEASURED_ON:\s*(\d{4}-\d{2}-\d{2})"
    r"|(?:[Mm]easured|[Ss]ettled)[^.\n]{0,24}?(\d{4}-\d{2}-\d{2})")
# A dollar figure with cents. "$70/month" is a rate, not a measurement, so
# require at least two decimals to catch the measured ones.
FIGURE = re.compile(r"\$\d+\.\d{2,}")


def problems_in(text, today, deployed_on=None):
    """deployed_on: ISO date the stack ran, when known."""
    out = []
    figures = FIGURE.findall(text)
    if not figures:
        return out

    m = STAMP.search(text)
    if not m:
        out.append("cost figure %s present with no measurement date -- "
                   "write \"Measured, settled <date>\" beside it"
                   % figures[0])
        return out

    measured = dt.date.fromisoformat(m.group(1) or m.group(2))
    if measured > today:
        out.append("the measurement date %s is in the future" % measured)
    elif (today - measured).days < 1:
        out.append("cost dated %s, which is today -- Cost Explorer still "
                   "reports this day as partial. Re-read tomorrow."
                   % measured)

    if deployed_on:
        ran = dt.date.fromisoformat(deployed_on)
        if measured <= ran:
            out.append("cost measured %s but the stack ran on %s -- the "
                       "usage cannot have been billed yet" % (measured, ran))
    return out


def self_test() -> int:
    today = dt.date(2026, 11, 20)
    cases = [
        ("no cost figure at all", "Nothing priced here.", None, 0),
        ("a rate is not a measurement", "The plan is $70/month.", None, 0),
        ("figure with no stamp", "Cost: $0.14 measured.", None, 1),
        ("figure stamped today",
         "Cost: $0.14 <!-- COST_MEASURED_ON: 2026-11-20 -->", None, 1),
        ("figure stamped yesterday",
         "Cost: $0.14 <!-- COST_MEASURED_ON: 2026-11-19 -->", None, 0),
        ("stamp in the future",
         "Cost: $0.14 <!-- COST_MEASURED_ON: 2026-11-25 -->", None, 1),
        ("measured the same day it ran",
         "Cost: $0.14 <!-- COST_MEASURED_ON: 2026-11-19 -->", "2026-11-19", 1),
        ("measured the day after it ran",
         "Cost: $0.14 <!-- COST_MEASURED_ON: 2026-11-19 -->", "2026-11-18", 0),
        ("the prose form the READMEs already use",
         "Measured, settled 2026-11-19: $0.1435.", None, 0),
        ("prose form, but dated today",
         "Measured, settled 2026-11-20: $0.1435.", None, 1),
    ]
    bad = 0
    for label, text, ran, want in cases:
        got = len(problems_in(text, today, ran))
        ok = got == want
        bad += not ok
        print("  [%s] %-34s -> %d, want %d"
              % (" ok " if ok else "FAIL", label, got, want))
    if bad:
        print("\nSELF-TEST FAILED")
        return 1
    print("\nself-test passed.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("week", nargs="?")
    ap.add_argument("--deployed-on")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    if not a.week:
        return self_test()

    path = os.path.join(ROOT, a.week, "README.md")
    if not os.path.exists(path):
        print("  no README at %s" % path)
        return 0

    text = io.open(path, encoding="utf-8").read()
    probs = problems_in(text, dt.date.today(), a.deployed_on)
    for p in probs:
        print("  %s" % p)
    if probs:
        print("\nA cost read before its day closed is an estimate wearing a "
              "measurement's clothes.")
        return 1
    print("  %s: cost figures are settled." % a.week)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
