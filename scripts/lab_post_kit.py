#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Take a lab post apart, and put it back together under the Master Standard.

    from lab_post_kit import extract, assemble

WHY THIS EXISTS (2026-10-25)
----------------------------
The Master Standard replaced the old ten-section weekly template, and 23 already
published AWS lab posts were written against the old one. Every single one is
missing the same six sections, so the transformation is repeatable even though
the prose is not.

What is mechanical lives here: pulling out the front matter, the architecture
SVG and each figure block by name; writing the result back; and refusing to
write a post that has lost something it should not have.

What is NOT mechanical stays with the author: a Lab Overview, a services table,
numbered architecture steps, prerequisites and a validation table cannot be
derived from the old markup. They come from reading the post and the repo.

THE RULES THIS ENFORCES, BECAUSE THEY ARE EASY TO BREAK AT VOLUME
-----------------------------------------------------------------
1. **The publish date never moves.** These posts are already live. Restructuring
   is not republishing, and `verified:` asserts that a human checked the vendor
   facts on a given day. Moving it without re-checking makes the badge a lie.
2. **No unsubstituted placeholders.** A `__FIG_07__` that silently survives is a
   broken image in a published post.
3. **Every figure referenced must exist in the source post**, so a typo cannot
   invent a screenshot that was never taken.
4. **The section ids and order are fixed**, so 23 posts cannot drift apart again.
"""
from __future__ import annotations

import io
import os
import re

SECTION_ORDER = [
    ("overview", "Lab Overview"),
    ("services", "Cloud Services and Concepts"),
    ("architecture", "Architecture and Workflow"),
    ("prerequisites", "Prerequisites"),
    ("implementation", "Implementation"),
    ("validation", "Validation and Evidence"),
    ("security-cost", "Security and Cost"),
    ("troubleshooting", "Troubleshooting and Lessons"),
    ("cleanup", "Cleanup and Key Takeaways"),
]


def extract(path):
    """Pull the reusable parts out of an existing post."""
    t = io.open(path, encoding="utf-8").read()
    parts = t.split("---", 2)
    if len(parts) < 3:
        raise SystemExit("no front matter in %s" % path)
    fm = parts[1]

    # The architecture diagram, however the post happened to wrap it.
    #
    # Only weeks 23-24 use <figure class="diagram">. Earlier posts use a bare
    # <svg>, <div class="arch-container"> or <div class="arch-wrap">. Rather
    # than special-case three wrappers, take the LARGEST svg on the page: the
    # architecture diagram runs 3-5k characters and the site's own icons are
    # 180-400, so the gap is not close. Everything is then re-wrapped in
    # <figure class="diagram">, which standardises 23 posts on the markup the
    # two newest already use.
    diagram = None
    svgs = re.findall(r"<svg.*?</svg>", t, re.S)
    if svgs:
        biggest = max(svgs, key=len)
        if len(biggest) > 1000:
            cap = re.search(
                r"<figcaption>(.*?)</figcaption>",
                t[t.index(biggest): t.index(biggest) + len(biggest) + 600], re.S)
            pieces = ['<figure class="diagram">', biggest]
            if cap:
                pieces.append("      <figcaption>%s</figcaption>" % cap.group(1))
            pieces.append("    </figure>")
            diagram = "\n".join(pieces)

    figs = {}
    for fb in re.findall(r'<figure class="screenshot">.*?</figure>', t, re.S):
        m = re.search(r"/([^/\"]+)\.png", fb)
        if m:
            figs[m.group(1)] = fb

    sections = {}
    for block, sid in re.findall(
            r'(<div class="section" id="([^"]+)".*?)(?=<div class="section"|\Z)', t, re.S):
        sections[sid] = block

    return {
        "raw": t,
        "fm": fm,
        "diagram": diagram or "",
        "figs": figs,
        "sections": sections,
        "title": (re.search(r"^title: (.*)$", fm, re.M) or [None, ""])[1]
                 if isinstance(re.search(r"^title: (.*)$", fm, re.M), type(None))
                 else re.search(r"^title: (.*)$", fm, re.M).group(1),
    }


def fig(src, name):
    """One figure block from the source post, by file stem. Fails if absent."""
    if name not in src["figs"]:
        raise SystemExit(
            "figure %r is not in this post. Available: %s"
            % (name, ", ".join(sorted(src["figs"])))
        )
    return src["figs"][name]


def words(html):
    body = re.sub(r"<svg.*?</svg>", "", html, flags=re.S)
    return len(re.sub(r"<[^>]+>", " ", body).split())


def assemble(path, src, body, *, min_words=1200, max_words=2600,
             min_figs=3, max_figs=8):
    """Write the restructured post, refusing anything obviously wrong."""
    out = "---\n" + src["fm"] + "---\n" + body

    leftover = re.findall(r"__[A-Z0-9_]+__", out)
    if leftover:
        raise SystemExit("unsubstituted placeholder(s): %s" % ", ".join(set(leftover)))

    ids = re.findall(r'<div class="section" id="([^"]+)"', out)
    want = [s for s, _ in SECTION_ORDER]
    if ids != want:
        raise SystemExit("section ids/order wrong.\n  got:  %s\n  want: %s" % (ids, want))

    if out.count('<div class="section"') != out.count("</div>"):
        raise SystemExit("unbalanced <div> in the assembled post")

    if "<svg" not in out:
        raise SystemExit("architecture diagram (inline <svg>) is missing")

    # the publish date must survive untouched
    for key in ("date:", "verified:"):
        before = re.search(r"^%s.*$" % key, src["fm"], re.M)
        after = re.search(r"^%s.*$" % key, out, re.M)
        if before and after and before.group(0) != after.group(0):
            raise SystemExit("%s changed - these posts are already published" % key)

    w = words(out.split("---", 2)[2])
    f = len(re.findall(r"<img ", out))
    if not (min_words <= w <= max_words):
        raise SystemExit("word count %d outside %d-%d" % (w, min_words, max_words))
    if not (min_figs <= f <= max_figs):
        raise SystemExit("figure count %d outside %d-%d" % (f, min_figs, max_figs))

    io.open(path, "w", encoding="utf-8", newline="\n").write(out)
    return {"words": w, "figures": f, "sections": len(ids)}


def report(name, stats):
    print("  %-44s %4dw  %d figs  %d sections" %
          (name, stats["words"], stats["figures"], stats["sections"]))
