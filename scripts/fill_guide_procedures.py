#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Write Deploy, Run it and Cleanup from the scripts each week actually ships.

    python scripts/fill_guide_procedures.py week-13 --write
    python scripts/fill_guide_procedures.py --all --write

Nearly every week ships scripts/deploy.sh, scripts/cleanup.sh and one or more
week-specific runners -- attack_simulation.sh, prove_isolation.sh,
prove_replay.sh, test_gate.sh, test_auth.sh, generate_signal.sh. They are the
real procedure, and most of them open with a comment block explaining what
they do and what should happen.

So these three sections are not written here so much as reported: the command
is the file that exists, and the description is that file's own header
comment. A reader can check both by opening the script.

Scripts are classified by name:

  deploy.sh, build_*.sh          -> 3. Deploy
  cleanup.sh                     -> 6. Cleanup
  validate.sh                    -> 5. Validation
  everything else                -> 4. Run it

A week with no runner gets a "4. Run it" that says the lab has no separate run
step and points at Deploy and Validation, rather than inventing one. That is a
true statement about some of these labs -- week 10 deploys a pipeline and
waits -- and an honest short section beats a padded one.
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

SKIP = {"__pycache__", "build-linkedin-card.py", "build_linkedin_card.py"}
RUNNABLE = (".sh", ".py")


def describe(path):
    """A script's own leading comment block, as prose."""
    lines = []
    for raw in io.open(path, encoding="utf-8", errors="replace"):
        s = raw.rstrip("\n")
        if s.startswith("#!"):
            continue
        if s.startswith("#"):
            body = s.lstrip("#").strip()
            if not body and not lines:
                continue
            if body.startswith("===") or set(body) == {"="}:
                continue
            lines.append(body)
            continue
        if lines:
            break
        if s.strip() in ("", "set -euo pipefail", "set -e"):
            continue
        break
    while lines and not lines[-1]:
        lines.pop()
    text = " ".join(x for x in lines if x).strip()
    text = re.sub(r"\s{2,}", " ", text)
    if len(text) > 400:
        # Cut at a sentence end, never mid-token: an earlier version stopped at
        # 400 characters and left descriptions ending "./attack_simulation.sh <"
        cut = text.rfind(". ", 0, 400)
        text = text[:cut + 1] if cut > 120 else text[:400].rsplit(" ", 1)[0]
    return text


def classify(name):
    low = name.lower()
    if low.startswith("deploy") or low.startswith("build"):
        return "3. Deploy"
    if low.startswith("cleanup") or low.startswith("destroy"):
        return "6. Cleanup"
    if low.startswith("validate") or low.startswith("verify"):
        return "5. Validation"
    return "4. Run it"


def scripts_for(wd):
    d = os.path.join(ROOT, wd, "scripts")
    if not os.path.isdir(d):
        return {}
    out = {}
    for f in sorted(os.listdir(d)):
        if f in SKIP or not f.endswith(RUNNABLE):
            continue
        out.setdefault(classify(f), []).append(f)
    return out


def block_for(section, wd, files):
    runner = "bash" if all(f.endswith(".sh") for f in files) else None
    lines = []
    for f in files:
        desc = describe(os.path.join(ROOT, wd, "scripts", f))
        cmd = "./scripts/%s" % f if f.endswith(".sh") else "python scripts/%s" % f
        lines.append("```bash\n%s\n```" % cmd)
        if desc:
            lines.append(desc)
    return "\n\n".join(lines)


NO_RUNNER = (
    "This lab has no separate run step. The workload is what the deploy "
    "creates, and what to look at afterwards is in "
    "[5. Validation](#5-validation)."
)


def insert(text, heading, body):
    """Insert a section in canonical position (before the next required one)."""
    order = ["1. Prerequisites", "2. Source files", "3. Deploy", "4. Run it",
             "5. Validation", "6. Cleanup", "Cost", "Troubleshooting",
             "References"]
    after = order[order.index(heading) + 1:]
    block = "\n## %s\n\n%s\n" % (heading, body)
    for nxt in after:
        m = re.search(r"^##\s+%s\b" % re.escape(nxt), text, re.M)
        if m:
            return text[:m.start()].rstrip() + "\n" + block + "\n" + text[m.start():]
    return text.rstrip() + "\n" + block


def apply(wd, write):
    p = os.path.join(ROOT, wd, "README.md")
    text = io.open(p, encoding="utf-8").read()
    found = scripts_for(wd)
    added = []
    for section in ("3. Deploy", "4. Run it", "5. Validation", "6. Cleanup"):
        if re.search(r"^##\s+%s\b" % re.escape(section.split(". ")[-1]
                                               if False else section[:4]),
                     text, re.M):
            pass
        pat = {"3. Deploy": r"^##\s+3\.\s*Deploy\b",
               "4. Run it": r"^##\s+4\.\s*Run\b",
               "5. Validation": r"^##\s+5\.\s*Validation\b",
               "6. Cleanup": r"^##\s+6\.\s*Cleanup\b"}[section]
        if re.search(pat, text, re.M):
            continue
        files = found.get(section)
        if not files:
            if section == "4. Run it":
                text = insert(text, section, NO_RUNNER)
                added.append("4. Run it (no runner: says so)")
            continue
        text = insert(text, section, block_for(section, wd, files))
        added.append("%s (%s)" % (section, ", ".join(files)))

    if not added:
        print("  %-40s nothing to fill from scripts" % wd)
        return 0
    if write:
        io.open(p, "w", encoding="utf-8", newline="\n").write(text)
    print("  %-40s %s" % (wd, "; ".join(added)))
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
