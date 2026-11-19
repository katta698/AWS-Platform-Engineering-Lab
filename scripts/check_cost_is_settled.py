#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""A cost figure read before its day closed is not the cost.

    python scripts/check_cost_is_settled.py week-28-rds-multi-region-failover
    python scripts/check_cost_is_settled.py --self-test

Cost Explorer reports the current day as partial and keeps revising it. A
figure taken the same day reads low -- week 27 published $0.078 and settled at
$0.1435, 84% higher. This refuses a cost claim read before its usage day
closed, and one carrying no date at all.

Pass --deployed-on with the UTC day the stack ran. Cost Explorer bills in UTC,
so an evening run in CST lands on the NEXT UTC day: week 28 ran on the evening
of 17 Nov local and every line of it was billed to 18 Nov UTC.

Either form counts, in the week's README:

    Measured, settled 2026-11-19: $0.1435.
    <!-- COST_MEASURED_ON: 2026-11-19 -->

A reading taken sooner than that is accepted only with evidence that the
figure stopped moving:

    <!-- COST_MEASURED_ON: 2026-11-19 COST_STABLE_OVER: 7h -->
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
# The explicit stamp wins. One pattern holding both forms returns whichever
# appears EARLIEST in the file, and a README line like "built, measured and
# destroyed 2026-11-17" is not a cost reading -- it matched first and failed
# the check against a date that had nothing to do with the bill.
STAMP_EXPLICIT = re.compile(r"COST_MEASURED_ON:\s*(\d{4}-\d{2}-\d{2})")
STAMP_PROSE = re.compile(
    r"(?:[Mm]easured|[Ss]ettled)[^.\n]{0,24}?(\d{4}-\d{2}-\d{2})")
# A dollar figure with cents. "$70/month" is a rate, not a measurement, so
# require at least two decimals to catch the measured ones.
FIGURE = re.compile(r"\$\d+\.\d{2,}")
# The day-count rule is a proxy for "Cost Explorer has stopped writing". Two
# readings hours apart that agree demonstrate that directly, so a recorded
# re-read is accepted in its place. Hours, so it cannot be satisfied by
# reading twice in a minute.
STABLE = re.compile(r"COST_STABLE_OVER:\s*(\d+)\s*h")
MIN_STABLE_HOURS = 6


def problems_in(text, today, deployed_on=None):
    """deployed_on: ISO date the stack ran, when known."""
    out = []
    figures = FIGURE.findall(text)
    if not figures:
        return out

    m = STAMP_EXPLICIT.search(text) or STAMP_PROSE.search(text)
    if not m:
        out.append("cost figure %s present with no measurement date -- "
                   "write \"Measured, settled <date>\" beside it"
                   % figures[0])
        return out

    measured = dt.date.fromisoformat(m.group(1))
    if measured > today:
        out.append("the measurement date %s is in the future" % measured)
        return out

    # What has to have closed is the day the USAGE fell on, not the day
    # before the reading. Cost Explorer bills in UTC days, so a stack run
    # late evening local lands on the next UTC day -- week 28 ran on the
    # evening of 17 Nov CST and every line of it was billed to 18 Nov UTC.
    # Reading on the day after the usage day is correct and must pass;
    # reading a day that is still open must not.
    if deployed_on:
        ran = dt.date.fromisoformat(deployed_on)
        # A closed day is not a complete one. Week 28 was read at 00:05 UTC,
        # five minutes after its usage day ended, and settled 58% higher: the
        # ARC line moved $0.0755 -> $0.1319 and RDS $0.1604 -> $0.2412. Cost
        # Explorer keeps writing a day's data for hours after midnight. Give
        # it a full day past the end of the usage day.
        st = STABLE.search(text)
        hours = int(st.group(1)) if st else 0
        if (measured - ran).days < 2 and hours < MIN_STABLE_HOURS:
            out.append("cost dated %s for usage on %s (UTC). Cost Explorer "
                       "was still filling that day in; read it no earlier "
                       "than %s, or record COST_STABLE_OVER: <hours>h after "
                       "re-reading it unchanged"
                       % (measured, ran, ran + dt.timedelta(days=2)))
    elif measured >= today:
        out.append("cost dated %s with no --deployed-on to check it against. "
                   "Pass the UTC day the stack ran, or re-read once it has "
                   "closed." % measured)
    return out


def self_test() -> int:
    today = dt.date(2026, 11, 20)
    cases = [
        ("no cost figure at all", "Nothing priced here.", None, 0),
        ("a rate is not a measurement", "The plan is $70/month.", None, 0),
        ("figure with no stamp", "Cost: $0.14 measured.", None, 1),
        ("stamped today, no usage day given",
         "Cost: $0.14 <!-- COST_MEASURED_ON: 2026-11-20 -->", None, 1),
        ("stamped yesterday, no usage day given",
         "Cost: $0.14 <!-- COST_MEASURED_ON: 2026-11-19 -->", None, 0),
        ("read the day after the usage day -- too soon, data still arriving",
         "Cost: $0.14 <!-- COST_MEASURED_ON: 2026-11-20 -->", "2026-11-19", 1),
        ("too soon, but re-read unchanged 7 hours later",
         "Cost: $0.14 <!-- COST_MEASURED_ON: 2026-11-20 COST_STABLE_OVER: 7h -->",
         "2026-11-19", 0),
        ("a re-read minutes later does not count",
         "Cost: $0.14 <!-- COST_MEASURED_ON: 2026-11-20 COST_STABLE_OVER: 1h -->",
         "2026-11-19", 1),
        ("read two days after the usage day",
         "Cost: $0.14 <!-- COST_MEASURED_ON: 2026-11-20 -->", "2026-11-18", 0),
        ("read while the usage day is still open",
         "Cost: $0.14 <!-- COST_MEASURED_ON: 2026-11-20 -->", "2026-11-20", 1),
        ("stamp in the future",
         "Cost: $0.14 <!-- COST_MEASURED_ON: 2026-11-25 -->", None, 1),
        ("measured the same day it ran",
         "Cost: $0.14 <!-- COST_MEASURED_ON: 2026-11-19 -->", "2026-11-19", 1),
        ("measured the day after it ran -- still too soon",
         "Cost: $0.14 <!-- COST_MEASURED_ON: 2026-11-19 -->", "2026-11-18", 1),
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
    # UTC, because the thing being judged is a UTC billing day. Reading a
    # closed UTC day during the preceding local evening is correct, and
    # comparing it to a local 'today' calls that date the future.
    probs = problems_in(text, dt.datetime.now(dt.timezone.utc).date(),
                        a.deployed_on)
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
