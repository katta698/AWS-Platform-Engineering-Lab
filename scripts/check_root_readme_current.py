#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""A week with a folder is not a planned week.

    python scripts/check_root_readme_current.py
    python scripts/check_root_readme_current.py --self-test

The root README's roadmap is the index a reader lands on. Its row for week N
must link to week-N's folder and not still say Planned once that folder
exists.
"""
from __future__ import annotations

import argparse
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def problems_in(readme, built_weeks):
    """built_weeks: {week number -> folder name}."""
    out = []
    for n in sorted(built_weeks):
        # Three shapes are in use: "| Week 19 |", "| [Week 13](...) |" and
        # zero-padded "| [Week 01](...) |". The trailing digit guard stops
        # week 1 matching the week 13 row.
        m = re.search(r"^\|\s*\[?Week 0*%d(?![0-9]).*$" % n, readme, re.M)
        if not m:
            out.append("week %d has a folder but no row in the roadmap" % n)
            continue
        row = m.group(0)
        if "Planned" in row:
            out.append("week %d is built but its row still says Planned" % n)
        if built_weeks[n] not in row:
            out.append("week %d's row does not link to %s"
                       % (n, built_weeks[n]))
    return out


def self_test() -> int:
    built = {7: "week-07-thing"}
    cases = [
        ("a built week linked and complete",
         "| Week 7 | [A thing](week-07-thing) | ... | Complete |", 0),
        ("still marked Planned",
         "| Week 7 | [A thing](week-07-thing) | ... | Planned |", 1),
        ("no link to the folder",
         "| Week 7 | A thing | ... | Complete |", 1),
        ("no row at all", "| Week 8 | Other | ... | Planned |", 1),
        ("the linked-number row shape is recognised",
         "| [Week 7](./week-07-thing) | A thing | ... | Complete |", 0),
        ("a zero-padded row is recognised",
         "| [Week 07](./week-07-thing) | A thing | ... | Complete |", 0),
        ("week 7 does not match the week 17 row",
         "| [Week 17](./week-17-other) | Other | ... | Complete |", 1),
    ]
    bad = 0
    for label, readme, want in cases:
        got = len(problems_in(readme, built))
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
    ap.add_argument("--self-test", action="store_true")
    if ap.parse_args().self_test:
        return self_test()

    built = {}
    for d in os.listdir(ROOT):
        m = re.match(r"week-(\d+)-", d)
        if m and os.path.isdir(os.path.join(ROOT, d)):
            built[int(m.group(1))] = d

    readme = io.open(os.path.join(ROOT, "README.md"), encoding="utf-8").read()
    probs = problems_in(readme, built)
    for p in probs:
        print("  %s" % p)
    print("\n%d week folder(s) checked, %d problem(s)." % (len(built), len(probs)))
    return 1 if probs else 0


if __name__ == "__main__":
    raise SystemExit(main())
