#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Fill the lab-guide sections that can be derived, and only those.

    python scripts/add_guide_sections.py week-21 --write

Two sections are facts about the repository rather than judgements about the
lab, so a tool can write them and a reader can verify them by looking:

  2. Source files   A compact tree of what actually builds the thing --
                    terraform, lambda and scripts. Docs, figures, screenshots,
                    lockfiles and build artefacts are left out, because the
                    master standard asks for the architecturally important
                    files and not an inventory.

  References        The published article, the week's own directory, and
                    nothing invented.

Everything else -- Prerequisites, Run it, Validation, Troubleshooting -- is a
judgement about the lab and is NOT written here. Those get added by hand, from
the post's own recorded evidence, or they stay missing and the shape check
keeps saying so.
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

CODE_DIRS = ("terraform", "lambda", "scripts", "src", "app", "k8s", "glue",
             "policies", "modules", ".github")
SKIP_PARTS = (".terraform", "docs", "screenshots", "figures", "linkedin",
              "__pycache__", "node_modules", ".git")
SKIP_EXT = (".zip", ".png", ".jpg", ".jpeg", ".gif", ".lock.hcl", ".pyc",
            ".tfstate", ".tfstate.backup")

POSTS = os.path.join(os.path.dirname(os.path.dirname(ROOT)),
                     "katta698-aws", "posts")


def code_files(week_dir):
    base = os.path.join(ROOT, week_dir)
    out = []
    for root, dirs, files in os.walk(base):
        dirs[:] = [d for d in dirs if d not in SKIP_PARTS]
        rel_root = os.path.relpath(root, base).replace("\\", "/")
        if rel_root == ".":
            rel_root = ""
        if rel_root and not rel_root.split("/")[0] in CODE_DIRS:
            continue
        for f in sorted(files):
            if f.startswith(".") and f != ".github":
                continue
            if any(f.endswith(e) for e in SKIP_EXT):
                continue
            if rel_root == "" and f.lower() in ("readme.md",):
                continue        # the guide does not list itself
            out.append((rel_root + "/" + f).lstrip("/"))
    return sorted(out)


def tree_block(paths):
    """A compact tree: directories with their files, deepest path shortened."""
    byd = {}
    for p in paths:
        d = os.path.dirname(p) or "."
        byd.setdefault(d, []).append(os.path.basename(p))
    lines = []
    for d in sorted(byd):
        lines.append("%s/" % d if d != "." else ".")
        for f in sorted(byd[d]):
            lines.append("  %s" % f)
    return "```\n" + "\n".join(lines) + "\n```"


def post_slug(week_num):
    if not os.path.isdir(POSTS):
        return None
    for fn in sorted(os.listdir(POSTS)):
        if not (fn.startswith("week-") and fn.endswith(".html")):
            continue
        m = re.match(r"week-(\d+)", fn)
        if not m or int(m.group(1)) != week_num:
            continue
        t = io.open(os.path.join(POSTS, fn), encoding="utf-8").read()
        fm = t.split("---", 2)[1] if t.count("---") >= 2 else ""
        if "AWS Weekly Lab" not in fm:
            continue
        s = re.search(r"^slug:\s*(.+)$", fm, re.M)
        return s.group(1).strip() if s else None
    return None


def insert_after(text, anchor_names, new_heading, body):
    """Put a section after the last of anchor_names that exists, else at end."""
    block = "\n## %s\n\n%s\n" % (new_heading, body)
    pos = None
    for name in anchor_names:
        m = re.search(r"^##\s+%s\s*$" % re.escape(name), text, re.M)
        if m:
            nxt = re.search(r"^##\s+", text[m.end():], re.M)
            pos = m.end() + (nxt.start() if nxt else len(text) - m.end())
    if pos is None:
        return text.rstrip() + "\n" + block
    return text[:pos].rstrip() + "\n" + block + text[pos:]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("week")
    ap.add_argument("--write", action="store_true")
    a = ap.parse_args()

    hits = [d for d in sorted(os.listdir(ROOT))
            if d.startswith("week-") and a.week in d
            and os.path.isdir(os.path.join(ROOT, d))]
    if len(hits) != 1:
        print("expected one week directory for %r, got %s" % (a.week, hits))
        return 1
    wd = hits[0]
    num = int(re.match(r"week-(\d+)", wd).group(1))
    p = os.path.join(ROOT, wd, "README.md")
    text = io.open(p, encoding="utf-8").read()
    did = []

    if not re.search(r"^##\s+2\.\s*Source files\s*$", text, re.M):
        files = code_files(wd)
        if files:
            body = ("What builds this. Documentation, figures and build "
                    "artefacts are left out.\n\n" + tree_block(files))
            text = insert_after(text, ["1. Prerequisites"], "2. Source files", body)
            did.append("2. Source files (%d files)" % len(files))

    if not re.search(r"^##\s+References\s*$", text, re.M):
        slug = post_slug(num)
        lines = []
        if slug:
            lines.append("- [The article for this week](https://jayanthkatta.com/"
                         "blog/%s/) &mdash; the problem, the findings and the "
                         "measured cost." % slug)
        lines.append("- [This week's source](https://github.com/katta698/"
                     "AWS-Platform-Engineering-Lab/tree/main/%s)" % wd)
        text = insert_after(text, ["Troubleshooting", "Cost", "6. Cleanup"],
                            "References", "\n".join(lines))
        did.append("References")

    if not did:
        print("  %-40s nothing derivable to add" % wd)
        return 0
    if a.write:
        io.open(p, "w", encoding="utf-8", newline="\n").write(text)
    print("  %-40s %s: %s" % (wd, "added" if a.write else "would add",
                              "; ".join(did)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
