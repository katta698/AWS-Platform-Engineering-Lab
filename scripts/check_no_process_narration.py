#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Committed files describe the control, not how they came to be written.

    python scripts/check_no_process_narration.py [week-NN-...]
    python scripts/check_no_process_narration.py --self-test

Keep "DAX caps cluster_name at 20 characters". Cut "the URL that cost a
redeploy". The test is whether the sentence helps a reader avoid breaking
something.

Out of scope, deliberately: READMEs (house narrative voice), lab-guide
Troubleshooting (real AWS failures belong there), BRIEFINGS.md (a sign-off
record), and this file (it quotes the banned phrases).
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

# Code and repo documentation. READMEs carry the house narrative voice and
# their Troubleshooting sections carry real failures, so they are not read.
EXTENSIONS = (".py", ".sh", ".tf", ".tftpl", ".yml", ".yaml")
ALSO = ("FIGURE_PLAN.md", "UNUSED.txt")

# BRIEFINGS.md is deliberately out of scope. It is a sign-off record, and who
# asked for which change IS its content -- "the design was widened to cover
# every scenario" loses the thing a decision log exists to preserve. The rule
# here is about narrating how a FILE came to be written, not about recording
# why a DESIGN is what it is.

# Each pattern names an authoring mishap, not a technical condition.
PATTERNS = [
    (r"\bgenerated ad hoc\b|\bmade ad hoc\b|\bproduced ad hoc\b",
     "an authoring mishap; say what the rule is instead"),
    (r"\bits source (?:was )?discarded\b|\bsource was thrown away\b",
     "an authoring mishap; say that sources are committed instead"),
    (r"\bnothing to re-export\b", "an authoring mishap"),
    (r"\bdid not (?:stop|prevent) it (?:here|again)\b",
     "narrates a past miss; state the control"),
    (r"\bfailure repeated\b|\bsame mistake again\b", "narrates a past miss"),
    (r"\bcost a redeploy\b|\bcost (?:me|us) (?:a|an|another)\b",
     "narrates what the authoring cost"),
    (r"\bJay (?:asked|had to ask|pointed out|noticed|said)\b",
     "names the reviewer; state the rule the review produced"),
    (r"\bI (?:guessed|forgot|missed|assumed|should have|wrote this|never)\b",
     "first-person authoring narrative"),
    (r"\bmy own (?:tooling|script|mistake|miss)\b",
     "first-person authoring narrative"),
    (r"\bthe honest answer was\b", "narrates a past miss"),
]
COMPILED = [(re.compile(p, re.I), why) for p, why in PATTERNS]


# This file quotes the banned phrases as examples of what to cut, so it would
# otherwise flag itself. A check that cannot pass on a clean tree is noise.
SELF = os.path.relpath(os.path.abspath(__file__), ROOT).replace(os.sep, "/")


def files_under(root, only=None):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames
                       if d not in (".git", "build", "__pycache__", "linkedin",
                                    ".terraform", "node_modules")]
        for f in filenames:
            if not (f.endswith(EXTENSIONS) or f in ALSO):
                continue
            p = os.path.join(dirpath, f)
            rel = os.path.relpath(p, ROOT).replace(os.sep, "/")
            if rel == SELF:
                continue
            if only and not rel.startswith(only):
                continue
            out.append((rel, p))
    return sorted(out)


def findings_in(text):
    out = []
    for i, line in enumerate(text.splitlines(), 1):
        for rx, why in COMPILED:
            m = rx.search(line)
            if m:
                out.append((i, m.group(0), why))
    return out


def self_test() -> int:
    cases = [
        ("a technical constraint is fine",
         "# DAX caps cluster_name at 20 characters, so the name differs.", 0),
        ("an upload-boundary explanation is fine",
         "# A remote run uploads only the root module directory.", 0),
        ("the agent transcript voice is fine",
         "I can help you manage this investigation.", 0),
        ("a README premise in Jay's voice is fine",
         "On 30 August I asked an AWS account what it was doing.", 0),
        ("a cost dimension is not a redeploy cost",
         "hides which dimension actually cost anything", 0),
        ("ad hoc generation is flagged",
         "a card generated ad hoc, its source discarded", 2),
        ("nothing to re-export is flagged",
         "and nothing to re-export when it needs changing", 1),
        ("naming the reviewer is flagged",
         "They exist because Jay asked what figure 05 was", 1),
        ("a past miss is flagged",
         "the check did not stop it here, because the script was new", 1),
        ("first-person authoring is flagged",
         "I guessed the fragment and moved on", 1),
    ]
    bad = 0
    for label, text, want in cases:
        got = len(findings_in(text))
        ok = got == want
        bad += not ok
        print("  [%s] %-42s -> %d, want %d"
              % (" ok " if ok else "FAIL", label, got, want))
    if bad:
        print("\nSELF-TEST FAILED")
        return 1
    print("\nself-test passed: authoring mishaps are detected; technical "
          "constraints, captured transcripts, README voice and the word "
          "'cost' in its ordinary sense are not.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="*")
    ap.add_argument("--self-test", action="store_true")
    a = ap.parse_args()
    if a.self_test:
        return self_test()

    only = a.paths[0] if a.paths else None
    checked = flagged = 0
    for rel, full in files_under(ROOT, only):
        checked += 1
        try:
            text = io.open(full, encoding="utf-8", errors="replace").read()
        except OSError:
            continue
        hits = findings_in(text)
        if not hits:
            continue
        flagged += 1
        print("  [FAIL] %s" % rel)
        for line_no, snippet, why in hits:
            print("           line %-5d %-34s %s"
                  % (line_no, repr(snippet)[:34], why))

    print("\n%d file(s) checked, %d carry process narration." % (checked, flagged))
    if flagged:
        print("Describe the control, not the incident. A comment should help "
              "the next person avoid breaking something.")
    return 1 if flagged else 0


if __name__ == "__main__":
    raise SystemExit(main())
