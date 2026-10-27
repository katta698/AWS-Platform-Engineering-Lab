#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Refuse to deploy a week that is not ready to be photographed.

    python scripts/check_before_deploy.py week-25-serverless-microservices

WHY THIS EXISTS (2026-10-27)
----------------------------
Jay: "Do I have to remind you for every lab to take screenshots? What am I
missing? Why are you missing?"

The honest answer was structural rather than careless. Every figure gate in
this repository runs AFTER the moment its figure was capturable:

    01-before-state                 capturable : BEFORE terraform apply
    check_figures_before_destroy.py runs       : before destroy
    check_lab_post_shape.py         runs       : at push

So the rule "capture the before-state at deploy time, never defer it" existed
in the instructions and in memory, and nothing enforced it at the only moment
it could be obeyed. The human was the gate. That is why the reminder kept
being needed.

A deploy is the point of no return for a whole class of evidence. An empty
console, a workspace with no resources, a region with no functions -- none of
these can be recreated once the stack exists. Tearing down and redeploying to
"recreate" one is staging evidence, not capturing it.

WHAT IT CHECKS
--------------
1. A FIGURE_PLAN.md exists. Planning figures after the build produces a list of
   what happened to be captured, which is not a plan.
2. Every figure the plan marks "before apply" has actually been captured.
3. The GitHub lab guide (README.md) exists -- the Master Standard requires two
   deliverables, and writing the reproducible half afterwards means writing it
   from memory instead of from the thing you just did.

It deliberately does NOT check figures due later. Those have their own gate
before destroy, and failing here on a figure that cannot exist yet would teach
everyone to pass --force.
"""
from __future__ import annotations

import argparse
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def rows(plan_text):
    """Figure rows from the plan's markdown table."""
    out = []
    for line in plan_text.splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) < 3 or not re.fullmatch(r"\d+", cells[0]):
            continue
        name = re.search(r"`([^`]+\.png)`", cells[1])
        out.append({
            "n": cells[0],
            "file": name.group(1) if name else None,
            "when": cells[-1].lower(),
            "what": cells[3] if len(cells) > 3 else "",
        })
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("week", help="week directory name")
    ap.add_argument("--force", action="store_true",
                    help="deploy anyway. Every use of this loses evidence that "
                         "cannot be recreated -- say so in the post if you use it.")
    args = ap.parse_args()

    wk = os.path.join(ROOT, args.week)
    if not os.path.isdir(wk):
        raise SystemExit("no such week: %s" % args.week)

    problems = []

    plan_path = os.path.join(wk, "docs", "FIGURE_PLAN.md")
    if not os.path.exists(plan_path):
        problems.append(
            "docs/FIGURE_PLAN.md is missing.\n"
            "      Write it BEFORE deploying. A plan written afterwards is a list of\n"
            "      what happened to be captured.")
        plan = []
    else:
        plan = rows(io.open(plan_path, encoding="utf-8").read())
        if not plan:
            problems.append("docs/FIGURE_PLAN.md has no figure table rows.")

    shots = os.path.join(wk, "docs", "blog", "screenshots")
    have = set(os.listdir(shots)) if os.path.isdir(shots) else set()

    pre = [r for r in plan if "before apply" in r["when"] or "before deploy" in r["when"]]
    for r in pre:
        if r["file"] and r["file"] not in have:
            problems.append(
                "figure %s (%s) is marked \"%s\" and has not been captured.\n"
                "      %s\n"
                "      This one cannot be recreated after the apply."
                % (r["n"], r["file"], r["when"].strip(), r["what"][:88]))

    if not os.path.exists(os.path.join(wk, "README.md")):
        problems.append(
            "README.md (the GitHub lab guide) is missing.\n"
            "      The Master Standard requires two deliverables. Written after the\n"
            "      build, the reproducible half gets written from memory rather than\n"
            "      from the thing you just did.")

    print("pre-deploy check: %s" % args.week)
    print("  figure plan      : %s" % ("found, %d figures" % len(plan) if plan else "MISSING"))
    print("  due before apply : %s" % (", ".join(r["file"] or r["n"] for r in pre) or "none"))
    print("  captured so far  : %d" % len(have))

    if not problems:
        print("\n  ready to deploy.")
        return 0

    print("\n  REFUSING TO DEPLOY -- %d problem(s):\n" % len(problems))
    for p in problems:
        print("    - %s" % p)
    print("\n  A deploy is the point of no return for before-state evidence.")
    if args.force:
        print("  --force given: proceeding anyway, and the post should say so.")
        return 0
    return 1


if __name__ == "__main__":
    sys.exit(main())
