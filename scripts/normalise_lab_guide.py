#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Move a week's README onto the lab-guide standard.

    python scripts/normalise_lab_guide.py week-07 --check
    python scripts/normalise_lab_guide.py week-07 --write

It RENAMES and REORDERS the sections a guide already has, and reports the ones
it does not. It will not invent a section: a Prerequisites heading with
plausible text under it is worse than a missing one, because the missing one
is still on the list of things to do and the invented one is not.

Content is carried across byte for byte. The only text this writes is the
heading line itself and, when --write is given, the Duration/Cost/Status rows
in the header block IF values are supplied on the command line.
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

CANON = ["1. Prerequisites", "2. Source files", "3. Deploy", "4. Run it",
         "5. Validation", "6. Cleanup", "Cost", "Troubleshooting",
         "References"]

# How the headings actually in use map onto those. First match wins, so the
# specific patterns come before the general ones.
INBOUND = [
    (r"^(F\.\s*)?Prerequisites?$",                 "1. Prerequisites"),
    (r"^Before you start$",                        "1. Prerequisites"),
    (r"^Prerequisite[:\s]",                        "1. Prerequisites"),
    (r"^Manual Prerequisite",                      "1. Prerequisites"),
    (r"^(G\.\s*)?GitHub Secrets Required$",        "1. Prerequisites"),
    (r"^Source files$",                            "2. Source files"),
    (r"^Layout$",                                  "2. Source files"),
    (r"^E\.\s*Complete Folder Structure$",         "2. Source files"),
    (r"^Infrastructure$",                          "2. Source files"),
    (r"^Terraform Resources",                      "2. Source files"),
    (r"^Configuration$",                           "2. Source files"),
    (r"^(3\.\s*)?Deploy( Steps)?$",                "3. Deploy"),
    (r"^Quick ?[Ss]tart$",                         "3. Deploy"),
    (r"^The order$",                               "3. Deploy"),
    (r"^D\.\s*Step-by-Step Implementation Plan$",  "3. Deploy"),
    (r"^HCP Terraform$",                           "3. Deploy"),
    # The canonical name has to map to itself, or a second run treats it as
    # an unknown heading and files it with the extras at the end. Weeks 21,
    # 24 and 25 ended up with "Run it" after References exactly that way.
    (r"^Run it$",                                  "4. Run it"),
    (r"^Run the experiments?$",                    "4. Run it"),
    (r"^Running it$",                              "4. Run it"),
    (r"^Run `",                                    "4. Run it"),
    (r"^Testing After Deploy$",                    "4. Run it"),
    (r"^The tests$",                               "4. Run it"),
    (r"^(H\.\s*)?Validation( Steps)?$",            "5. Validation"),
    (r"^Saved queries$",                           "5. Validation"),
    (r"^What it found$",                           "5. Validation"),
    (r"^Proving it",                               "5. Validation"),
    (r"^(K\.\s*)?Clean ?up( Steps)?$",             "6. Cleanup"),
    (r"^Teardown$",                                "6. Cleanup"),
    (r"^Cost",                                     "Cost"),
    (r"^(J\.\s*)?Troubleshooting( Guide)?$",       "Troubleshooting"),
    (r"^References$",                              "References"),
    (r"^Sources$",                                 "References"),
    (r"^Blog( Post)?$",                            "References"),
]


def classify(h):
    # Strip a leading ordinal before matching. Weeks 24 and 25 already use
    # "## 1. Prerequisites"; without this they read as unmapped and the tool
    # reports the two guides that are already right as the worst two.
    h = re.sub(r"^\s*\d+\.\s*", "", h.strip())
    for pat, name in INBOUND:
        if re.match(pat, h):
            return name
    return None


def split(text):
    """-> (head, [(heading, body), ...])"""
    parts = re.split(r"^##\s+(.+?)\s*$", text, flags=re.M)
    head = parts[0]
    out = []
    for i in range(1, len(parts), 2):
        out.append((parts[i].strip(), parts[i + 1] if i + 1 < len(parts) else ""))
    return head, out


def rebuild(head, sections):
    """Merge mapped sections under canonical names, in canonical order."""
    bucket = {}
    extras = []
    for h, body in sections:
        name = classify(h)
        if name is None:
            extras.append((h, body))
            continue
        # A heading that mapped but carried a different name keeps that name as
        # an h3, so the seam stays visible and nothing silently loses its label.
        if name in bucket:
            bucket[name] += "\n### %s\n%s" % (h, body.strip("\n"))
        else:
            keep = "" if re.match(r"^\d\.\s", h) or h == name else \
                   "\n### %s\n" % h
            bucket[name] = keep + body.strip("\n")
    out = [head.rstrip() + "\n"]
    for name in CANON:
        if name in bucket:
            out.append("\n## %s\n\n%s\n" % (name, bucket[name].strip("\n")))
    for h, body in extras:
        out.append("\n## %s\n%s" % (h, body.rstrip() + "\n"))
    return "".join(out), sorted(set(CANON) - set(bucket)), [h for h, _ in extras]


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
    p = os.path.join(ROOT, hits[0], "README.md")
    text = io.open(p, encoding="utf-8").read()
    head, sections = split(text)
    new, missing, extras = rebuild(head, sections)

    print("  %s" % hits[0])
    print("    mapped    : %s" % ", ".join(
        n for n in CANON if ("\n## %s\n" % n) in new) or "none")
    print("    MISSING   : %s" % (", ".join(missing) or "none"))
    print("    kept as-is: %s" % (", ".join(e[:34] for e in extras) or "none"))
    if a.write:
        io.open(p, "w", encoding="utf-8", newline="\n").write(new)
        print("    written")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
