#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Give each lab guide the header block the standard asks for.

    python scripts/add_guide_header.py week-07 --write
    python scripts/add_guide_header.py --all --write

Every value is lifted from the week's published article, which is Jay's own
text and carries the measured figures:

  title           the article's post-title
  What you build  the article's "The objective." sentence, or its subtitle
  Cost            the money phrase from the article's post-meta, which is
                  where the measured cost is recorded
  Status          built and validated / destroyed, from the same meta

Weeks 1-9 and 19 record no money phrase in their post-meta, so their Cost row
is set explicitly in OVERRIDES below, each one read out of that week's own
Cost section. Where an article states only per-resource rates and never a
total, the row SAYS so rather than adding the rates up and presenting the
result as though it had been measured.

This is ADDITIVE. Several guides open with 100-170 words of real
introduction, and that is kept; only the missing pieces are inserted. An
earlier version of this script replaced the whole head, which would have
deleted all of it.
"""
from __future__ import annotations

import argparse
import html
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
POSTS = os.path.join(os.path.dirname(os.path.dirname(ROOT)),
                     "katta698-aws", "posts")

MONEY = re.compile(r"(\$|no hourly|free)", re.I)

OVERRIDES = {
    1: "~$65/month if left running; destroyed after the lab",
    2: "~$75/month if left running; destroyed after the lab",
    3: "estimated per resource in the article; no measured total recorded",
    4: "per-run; estimated in the article, no measured total recorded",
    5: "~$0 &mdash; every component is free at this scale",
    6: "~$0 &mdash; Organizations and SCPs are free, Step Functions under "
       "$0.001 per vend",
    7: "Free &mdash; Identity Center, permission sets and assignments carry "
       "no charge",
    8: "estimated per rate in the article; no measured total recorded",
    9: "~$18/month if left running; destroyed after the lab",
    19: "$1.21 measured from Cost Explorer; destroyed",
}


def plain(s):
    return html.unescape(re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", s))).strip()


def post_for(num):
    for fn in sorted(os.listdir(POSTS)):
        if not (fn.startswith("week-") and fn.endswith(".html")):
            continue
        m = re.match(r"week-(\d+)", fn)
        if not m or int(m.group(1)) != num:
            continue
        t = io.open(os.path.join(POSTS, fn), encoding="utf-8").read()
        fm = t.split("---", 2)[1] if t.count("---") >= 2 else ""
        if "AWS Weekly Lab" in fm:
            return t
    return None


def facts(post, num):
    out = {"title": None, "build": None, "cost": None, "status": None,
           "stack": None}
    m = re.search(r'<div class="post-title">(.*?)</div>', post, re.S)
    if m:
        out["title"] = plain(m.group(1))
    m = re.search(r"<strong>The objective\.</strong>(.*?)</p>", post, re.S)
    if m:
        out["build"] = plain(m.group(1))
    else:
        m = re.search(r'<div class="post-subtitle">(.*?)</div>', post, re.S)
        if m:
            out["build"] = plain(m.group(1))
    m = re.search(r'<div class="post-meta">(.*?)</div>', post, re.S)
    if m:
        spans = [plain(s) for s in
                 re.findall(r"<span>(.*?)</span>", m.group(1), re.S)]
        for s in spans:
            if MONEY.search(s):
                out["cost"] = s
            elif "Terraform" in s or "HCP" in s:
                out["stack"] = s
    if not out["cost"]:
        out["cost"] = OVERRIDES.get(num)
    if out["cost"] and re.search(r"destroy", out["cost"], re.I):
        out["status"] = "built, validated and destroyed."
    return out


def apply(wd, write):
    num = int(re.match(r"week-(\d+)", wd).group(1))
    post = post_for(num)
    if post is None:
        print("  %-40s no article found" % wd)
        return 1
    f = facts(post, num)
    p = os.path.join(ROOT, wd, "README.md")
    text = io.open(p, encoding="utf-8").read()
    marker = "\n## "
    cut = text.index(marker) if marker in text else len(text)
    head, body = text[:cut], text[cut:]
    added = []

    if not re.search(r"^#\s+\S", head, re.M):
        head = "# Week %d — %s\n\n" % (num, f["title"] or "") + head
        added.append("H1")

    if "What you build:" not in head and f["build"]:
        m = re.search(r"^#\s+.*$", head, re.M)
        at = m.end() if m else 0
        head = head[:at] + "\n\n**What you build:** " + f["build"] + head[at:]
        added.append("What you build")

    if not re.search(r"\|\s*\*\*Cost\*\*\s*\|", head):
        rows = "| | |\n|---|---|\n| **Cost** | %s |" % (
            f["cost"] or "not recorded in the article")
        if f["stack"]:
            rows += "\n| **Provisioning** | %s |" % f["stack"]
        head = head.rstrip() + "\n\n" + rows + "\n"
        added.append("Cost row")

    if not re.search(r"(?mi)^>\s*\*\*Status", head):
        head = head.rstrip() + "\n\n> **Status:** %s\n" % (
            f["status"] or "built and validated.")
        added.append("Status")

    if not added:
        print("  %-40s header already complete" % wd)
        return 0
    if write:
        io.open(p, "w", encoding="utf-8", newline="\n").write(head + body)
    print("  %-40s %s: %s"
          % (wd, "added" if write else "would add", ", ".join(added)))
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("week", nargs="?")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()
    dirs = sorted(d for d in os.listdir(ROOT)
                  if d.startswith("week-")
                  and os.path.isdir(os.path.join(ROOT, d)))
    if not a.all:
        dirs = [d for d in dirs if a.week and a.week in d]
    rc = 0
    for d in dirs:
        rc |= apply(d, a.write)
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
