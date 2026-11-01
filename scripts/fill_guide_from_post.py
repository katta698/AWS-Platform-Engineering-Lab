#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Carry Prerequisites, Validation and Troubleshooting across from the article.

    python scripts/fill_guide_from_post.py week-10 --write
    python scripts/fill_guide_from_post.py --all --write

The published articles now carry, for every week:

  a Prerequisites table      Requirement | Why | How to check
  a Validation table         Test | Expected | Actual | Status
  Troubleshooting entries    Problem / Root cause / Resolution / Lesson

Those were written from each lab's own recorded evidence, so the guide takes
them rather than restating them differently and drifting.

Two deliberate differences in what is carried:

  Validation  takes Test and Expected only. A guide tells you what to run and
              what should happen; the Actual column is a record of one
              particular run and belongs in the article. Carrying it would
              make a runbook read like a history.

  Troubleshooting  takes Problem, Root cause and Resolution, and drops the
              Lesson. The lesson is the article's editorial point. What a
              person wants at 2am is the symptom and the fix.

Nothing is generated. If an article has no such section the guide gets
nothing and the shape check keeps reporting it.
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
BLOG = os.path.join(os.path.dirname(os.path.dirname(ROOT)), "katta698-aws")
POSTS = os.path.join(BLOG, "posts")
sys.path.insert(0, os.path.join(BLOG, "scripts"))

ORDER = ["1. Prerequisites", "2. Source files", "3. Deploy", "4. Run it",
         "5. Validation", "6. Cleanup", "Cost", "Troubleshooting",
         "References"]


def md(s):
    """HTML fragment -> markdown-ish inline text."""
    s = re.sub(r"<br\s*/?>", " ", s)
    s = re.sub(r"<code[^>]*>(.*?)</code>", r"`\1`", s, flags=re.S)
    s = re.sub(r"<strong>(.*?)</strong>", r"**\1**", s, flags=re.S)
    s = re.sub(r"<em>(.*?)</em>", r"*\1*", s, flags=re.S)
    s = re.sub(r"<[^>]+>", "", s)
    s = html.unescape(s)
    return re.sub(r"\s+", " ", s).strip().replace("|", "\\|")


def post_text(num):
    for fn in sorted(os.listdir(POSTS)):
        if not (fn.startswith("week-") and fn.endswith(".html")):
            continue
        m = re.match(r"week-(\d+)", fn)
        if not m or int(m.group(1)) != num:
            continue
        t = io.open(os.path.join(POSTS, fn), encoding="utf-8").read()
        if "AWS Weekly Lab" in (t.split("---", 2)[1] if t.count("---") >= 2 else ""):
            return t
    return None


def section(text, sid):
    m = re.search(r'<div class="section" id="%s".*?(?=<div class="section"|\Z)'
                  % re.escape(sid), text, re.S)
    if m:
        return m.group(0)
    m = re.search(r'<h2[^>]*id="%s"[^>]*>.*?(?=<h2|\Z)' % re.escape(sid),
                  text, re.S)
    return m.group(0) if m else None


def rows_of(table_html):
    out = []
    for tr in re.findall(r"<tr>(.*?)</tr>", table_html, re.S):
        cells = [md(c) for c in
                 re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", tr, re.S)]
        if cells:
            out.append(cells)
    return out


def table_md(rows):
    if not rows:
        return None
    head, body = rows[0], rows[1:]
    lines = ["| " + " | ".join(head) + " |",
             "|" + "|".join(["---"] * len(head)) + "|"]
    for r in body:
        r = (r + [""] * len(head))[:len(head)]
        lines.append("| " + " | ".join(r) + " |")
    return "\n".join(lines)


def prerequisites(post):
    sec = section(post, "prerequisites")
    if not sec:
        return None
    m = re.search(r"<table.*?</table>", sec, re.S)
    return table_md(rows_of(m.group(0))) if m else None


def validation(post):
    sec = section(post, "validation")
    if not sec:
        return None
    m = re.search(r"<table.*?</table>", sec, re.S)
    if not m:
        return None
    rows = rows_of(m.group(0))
    if not rows or len(rows[0]) < 2:
        return None
    trimmed = [r[:2] for r in rows]          # Test | Expected
    body = table_md(trimmed)
    return (body + "\n\nThe results recorded when this lab was built are in "
                   "the article.")


def troubleshooting(post):
    sec = section(post, "troubleshooting")
    if not sec:
        return None
    out = []
    for p in re.findall(r"<p>(.*?)</p>", sec, re.S):
        if "Root cause" not in p:
            continue
        txt = md(p)
        parts = {}
        for key in ("Problem", "Root cause", "Resolution"):
            m = re.search(r"\*\*%s\.\*\*(.*?)(?=\*\*(?:Problem|Root cause|"
                          r"Resolution|Lesson)\.\*\*|$)" % key, txt, re.S)
            if m:
                parts[key] = m.group(1).strip()
        if not parts.get("Problem"):
            continue
        entry = ["**%s**" % parts["Problem"].rstrip(".") + "."]
        if parts.get("Root cause"):
            entry.append("%s" % parts["Root cause"])
        if parts.get("Resolution"):
            entry.append("*Fix:* %s" % parts["Resolution"])
        out.append("\n".join(entry))
    return "\n\n".join(out) if out else None


def insert(text, heading, body):
    after = ORDER[ORDER.index(heading) + 1:]
    block = "\n## %s\n\n%s\n" % (heading, body)
    for nxt in after:
        pat = r"^##\s+%s\b" % re.escape(nxt.split(". ")[-1] if ". " in nxt else nxt)
        pat = r"^##\s+%s\b" % re.escape(nxt)
        m = re.search(pat, text, re.M)
        if m:
            return text[:m.start()].rstrip() + "\n" + block + "\n" + text[m.start():]
    return text.rstrip() + "\n" + block


def apply(wd, write):
    num = int(re.match(r"week-(\d+)", wd).group(1))
    post = post_text(num)
    if post is None:
        print("  %-40s no article" % wd)
        return 1
    p = os.path.join(ROOT, wd, "README.md")
    text = io.open(p, encoding="utf-8").read()
    added = []
    for heading, pat, fn in (
            ("1. Prerequisites", r"^##\s+1\.\s*Prerequisites\b", prerequisites),
            ("5. Validation", r"^##\s+5\.\s*Validation\b", validation),
            ("Troubleshooting", r"^##\s+Troubleshooting\b", troubleshooting)):
        if re.search(pat, text, re.M):
            continue
        body = fn(post)
        if not body:
            continue
        text = insert(text, heading, body)
        added.append(heading)
    if not added:
        print("  %-40s nothing carried" % wd)
        return 0
    if write:
        io.open(p, "w", encoding="utf-8", newline="\n").write(text)
    print("  %-40s %s" % (wd, ", ".join(added)))
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
