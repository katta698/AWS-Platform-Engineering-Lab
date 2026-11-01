#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Hold every week's README to one shape.

    python scripts/check_lab_guide_shape.py
    python scripts/check_lab_guide_shape.py week-07
    python scripts/check_lab_guide_shape.py --self-test

WHY THIS EXISTS (2026-11-01)
----------------------------
The blog posts have had a blocking shape check since 2026-10-25 and all 25 now
share one heading sequence. The lab guides had nothing, and drifted into
roughly 25 different shapes: week 1 used lettered sections (A. Business
Problem ... M. Enterprise Best Practices), weeks 2-3 used
Architecture / Multi-Tenant Design / Quick Start, weeks 11-15 used lowercase
Quick start / Security patterns / Teardown, and only weeks 24-25 used the
numbered runbook that actually reads like something you follow.

Jay asked why consistency kept slipping. The answer each time was the same:
the rule lived in a document and the document is not consulted while typing.
So this is a check, and it blocks.

WHAT IT REQUIRES

  A header block carrying
    * an H1 title
    * a "What you build:" line, so the reader knows within one line
    * a facts table with a Cost row -- what a reader wants to know BEFORE
      starting, and something AWS's own lab format puts up front that this
      series did not

      DURATION IS NOT REQUIRED, and that is deliberate. AWS states "requires
      approximately 60 minutes" on every lab and it is genuinely useful, but
      no figure was ever recorded for these twenty-five. Writing one per week
      would mean inventing twenty-five numbers that look measured. The field
      is worth adding once Jay supplies real values; until then its absence
      is honest and its presence would not be.
    * a Status line

  Then these nine headings, in this order:

    1. Prerequisites      2. Source files   3. Deploy
    4. Run it             5. Validation     6. Cleanup
    Cost                  Troubleshooting   References

WHAT IT DELIBERATELY ALLOWS

Extra sections, anywhere. A guide may carry Architecture, Security patterns,
or a design-rationale section, and several carry good ones. The nine above are
a floor, not a cage: a check that deleted twenty-five weeks of rationale to
make a list match would be a worse outcome than the drift it fixed.

Step 4's noun varies with the lab -- "Run it", "Run the experiment", "Run the
experiments" are all accepted, because some weeks run a workload and some run
an experiment against one.
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

# (canonical name, regex the heading must match)
REQUIRED = [
    ("1. Prerequisites",  r"^1\.\s*Prerequisites$"),
    ("2. Source files",   r"^2\.\s*Source files$"),
    ("3. Deploy",         r"^3\.\s*Deploy$"),
    ("4. Run it",         r"^4\.\s*Run (it|the experiment|the experiments)$"),
    ("5. Validation",     r"^5\.\s*Validation$"),
    ("6. Cleanup",        r"^6\.\s*Cleanup$"),
    ("Cost",              r"^Cost\b"),
    ("Troubleshooting",   r"^Troubleshooting$"),
    ("References",        r"^References$"),
]


def headings(text):
    return [h.strip() for h in re.findall(r"^##\s+(.+?)\s*$", text, re.M)]


def check_text(text):
    """-> list of problems, empty when the guide is in shape."""
    problems = []
    hs = headings(text)

    if not re.search(r"^#\s+\S", text, re.M):
        problems.append("no H1 title")
    if "What you build:" not in text:
        problems.append('no "What you build:" line')

    head = text.split("\n## ", 1)[0]
    if not re.search(r"\|\s*\*\*Cost\*\*\s*\|", head):
        problems.append("the header table has no Cost row")
    if not re.search(r"(?mi)^>\s*\*\*Status", head):
        problems.append("no Status line")

    # Required headings, present and in order.
    seen = []
    for name, pat in REQUIRED:
        idx = next((i for i, h in enumerate(hs) if re.match(pat, h)), None)
        if idx is None:
            problems.append('no "%s" section' % name)
        else:
            seen.append((name, idx))
    ordered = [n for n, _ in sorted(seen, key=lambda x: x[1])]
    expected = [n for n, _ in REQUIRED if n in {s for s, _ in seen}]
    if ordered != expected:
        problems.append("sections out of order: %s" % " -> ".join(ordered))

    return problems


def self_test() -> int:
    good = """# Week 99 - A Lab

**What you build:** one thing that does one job.

| | |
|---|---|
| **Duration** | ~45 minutes |
| **Cost** | ~$0.40 if run to completion |

> **Status:** built and validated.

## 1. Prerequisites
## 2. Source files
## 3. Deploy
## 4. Run it
## 5. Validation
## 6. Cleanup
## Cost
## Troubleshooting
## References
"""
    cases = [
        ("a guide in shape", good, 0),
        ("no Duration row is NOT a fault",
         good.replace("| **Duration** | ~45 minutes |", ""), 0),
        ("no Cost row", good.replace("| **Cost** | ~$0.40 if run to completion |", ""), 1),
        ("no What you build line",
         good.replace("**What you build:** one thing that does one job.", ""), 1),
        ("no Status", good.replace("> **Status:** built and validated.", ""), 1),
        ("a missing section", good.replace("## 5. Validation\n", ""), 1),
        ("sections out of order",
         good.replace("## 3. Deploy\n## 4. Run it\n", "## 4. Run it\n## 3. Deploy\n"), 1),
        ("the experiment wording for step 4",
         good.replace("## 4. Run it", "## 4. Run the experiment"), 0),
        ("an extra section is allowed",
         good.replace("## Cost", "## Architecture\n## Cost"), 0),
    ]
    bad = 0
    for label, text, want in cases:
        got = len(check_text(text))
        ok = got == want
        bad += not ok
        print("  [%s] %s -> %d problem(s), want %d"
              % (" ok " if ok else "FAIL", label, got, want))
    if bad:
        print("\nSELF-TEST FAILED")
        return 1
    print("\nself-test passed: a missing section, a missing Cost row, a missing "
          "Status and a reordering are all detected; a missing Duration row and "
          "an extra section are not faults.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("weeks", nargs="*")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()

    dirs = sorted(d for d in os.listdir(ROOT)
                  if d.startswith("week-") and os.path.isdir(os.path.join(ROOT, d)))
    if a.weeks:
        dirs = [d for d in dirs if any(w in d for w in a.weeks)]
    if not dirs:
        print("NOTHING MATCHED %s -- a run that inspected no guide has not "
              "passed." % ", ".join(a.weeks))
        return 1

    checked = failed = 0
    for d in dirs:
        p = os.path.join(ROOT, d, "README.md")
        if not os.path.exists(p):
            print("  [FAIL] %-40s no README.md" % d)
            failed += 1
            continue
        checked += 1
        problems = check_text(io.open(p, encoding="utf-8").read())
        if not problems:
            print("  [ ok ] %s" % d)
            continue
        failed += 1
        print("  [FAIL] %s" % d)
        for pr in problems:
            print("           %s" % pr)

    print("\n%d guide(s) checked, %d need work." % (checked, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
