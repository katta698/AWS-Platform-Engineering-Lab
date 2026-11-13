#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Report what last week's post has that this week's does not.

    python scripts/check_against_previous_week.py 26
    python scripts/check_against_previous_week.py --self-test

check_lab_post_shape.py enforces a floor: nine sections, 4-7 figures, an SVG.
Anything conventional but unchecked can go missing and still pass. Week 26
shipped without a References list, without a key for its numbered diagram
paths, and with no AWS console figure -- all three present in week 25, all
three passing every check.

This compares the two and prints the difference. It is not a style
judgement: only "week N-1 has this, week N does not".
"""
from __future__ import annotations

import argparse
import io
import os
import re
import subprocess
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BLOG = os.path.join(os.path.dirname(os.path.dirname(ROOT)), "katta698-aws")
assert os.path.isdir(BLOG), "blog repo not found at %s" % BLOG


def post_path(week):
    out = subprocess.run([sys.executable, "scripts/aws_post_path.py", str(week)],
                         cwd=BLOG, capture_output=True, text=True)
    p = out.stdout.strip()
    return p if p and os.path.exists(p) else None


def structural_headings(before_week, threshold=0.6):
    """h3s that recur across past posts. A heading in most weeks is part of
    the shape; one in a single week is that week's content."""
    import collections
    c, n = collections.Counter(), 0
    for w in range(1, before_week):
        p = post_path(w)
        if not p:
            continue
        n += 1
        t = io.open(p, encoding="utf-8").read()
        for h in {x.strip().lower() for x in re.findall(r"<h3>(.*?)</h3>", t, re.S)}:
            c[re.sub(r"<[^>]+>", "", h)] += 1
    return {h for h, k in c.items() if n and k >= n * threshold}


def shape(text):
    """The structural facts worth comparing."""
    imgs = re.findall(r"<img[^>]*>", text)
    # Source is judged from the filename AND the alt text. Filenames alone
    # undercount: a CloudWatch capture named 04-cloudwatch-ecpus.png is a
    # console figure whether or not the word "console" is in its name.
    console = re.compile(r"console|hcp|cloudwatch|terraform\.io", re.I)
    return {
        "sections": set(re.findall(r'<div class="section" id="([^"]+)"', text)),
        "h3": {h.strip().lower() for h in re.findall(r"<h3>(.*?)</h3>", text, re.S)},
        "figures": len(imgs),
        "console_figures": sum(1 for i in imgs if console.search(i)),
        "ordered_lists": len(re.findall(r"<ol>", text)),
        "tables": len(re.findall(r"<table", text)),
        "svg": len(re.findall(r"<svg", text)),
    }


def compare(prev, cur, structural=None):
    """-> list of findings. Empty when this week carries everything.

    `structural` limits the heading comparison to headings that recur across
    weeks. Without it every content heading differs and the output is noise.
    """
    a, b = shape(prev), shape(cur)
    out = []
    for m in sorted(a["sections"] - b["sections"]):
        out.append("section present last week, absent this week: %s" % m)
    missing_h3 = a["h3"] - b["h3"]
    if structural is not None:
        missing_h3 &= structural
    for m in sorted(missing_h3):
        out.append("heading present last week, absent this week: %s" % m)
    for name, label in (("figures", "figures"),
                        ("console_figures", "console/HCP figures"),
                        ("ordered_lists", "ordered lists"),
                        ("tables", "tables"),
                        ("svg", "inline SVG diagrams")):
        if b[name] < a[name]:
            out.append("fewer %s than last week: %d vs %d" % (label, b[name], a[name]))
    return out


def self_test() -> int:
    base = ('<div class="section" id="overview"></div>'
            '<div class="section" id="cleanup"><h3>References</h3></div>'
            '<ol></ol><table></table><svg></svg>'
            '<img src="01-a.png"><img src="02-console-b.png">')
    cases = [
        ("identical posts", base, base, 0),
        ("References dropped", base, base.replace("<h3>References</h3>", ""), 1),
        ("a section dropped", base,
         base.replace('<div class="section" id="overview"></div>', ""), 1),
        ("the walkthrough dropped", base, base.replace("<ol></ol>", ""), 1),
        ("the console figure dropped", base,
         base.replace('<img src="02-console-b.png">', ""), 2),
        ("extra content is not a finding", base,
         base + '<ol></ol><img src="03-c.png">', 0),
        ("a week-specific heading is not a finding",
         base + "<h3>Concurrency is a multiplication</h3>", base, 0),
    ]
    bad = 0
    for label, prev, cur, want in cases:
        got = len(compare(prev, cur, structural={"references"}))
        ok = got == want
        bad += not ok
        print("  [%s] %-34s -> %d, want %d"
              % (" ok " if ok else "FAIL", label, got, want))
    if bad:
        print("\nSELF-TEST FAILED")
        return 1
    print("\nself-test passed: dropped sections, headings, figures, console "
          "figures and walkthroughs are reported; extra content is not.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("week", nargs="?", type=int)
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()
    if not a.week:
        ap.error("give a week number")

    cur_p, prev_p = post_path(a.week), post_path(a.week - 1)
    if not cur_p:
        print("no post found for week %d" % a.week)
        return 1
    if not prev_p:
        print("no week %d post to compare against -- nothing to do" % (a.week - 1))
        return 0

    findings = compare(io.open(prev_p, encoding="utf-8").read(),
                       io.open(cur_p, encoding="utf-8").read(),
                       structural=structural_headings(a.week))
    print("week %d vs week %d" % (a.week, a.week - 1))
    if not findings:
        print("  carries everything week %d had." % (a.week - 1))
        return 0
    for f in findings:
        print("  %s" % f)
    print("\n%d difference(s). Each is something last week's reader got and "
          "this week's would not." % len(findings))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
