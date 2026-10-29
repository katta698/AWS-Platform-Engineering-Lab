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

    # The chrome: everything above the first section -- the jk-post wrapper,
    # the post-header (eyebrow/title/subtitle/meta) and the old table of
    # contents. Ten posts lost all of it before this was captured, because the
    # build replaced the whole body and extract() only ever took sections.
    body = parts[2]
    first = body.find('<div class="section"')
    preamble = body[:first] if first > 0 else ""
    header = ""
    hm = re.search(r'(<div id="jk-post">.*?</div>\s*</div>)', preamble, re.S)
    if hm:
        header = hm.group(1)
    else:
        hm = re.search(r'(<div class="post-header">.*?</div>\s*</div>)', preamble, re.S)
        if hm:
            header = '<div id="jk-post">' + "\n\n" + hm.group(1)

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
        "preamble": preamble,
        "header": header,
        "title": (re.search(r"^title: (.*)$", fm, re.M) or [None, ""])[1]
                 if isinstance(re.search(r"^title: (.*)$", fm, re.M), type(None))
                 else re.search(r"^title: (.*)$", fm, re.M).group(1),
    }


def chrome(src):
    """The post header, plus a table of contents for the NEW sections.

    The header -- eyebrow, title, subtitle, and the date/tools/cost meta line
    -- is carried over VERBATIM. It is the post's own record of what it is and
    when it ran, and not the restructure's to rewrite.

    The table of contents is REGENERATED, because the old one links to #why,
    #how, #challenges and friends, which do not exist after a restructure.
    Carrying it over would produce a menu of dead links that looks perfectly
    fine until somebody clicks one.
    """
    if not src["header"]:
        raise SystemExit(
            "this post has no post-header to carry over. Weeks 1-3 and 5 never "
            "had one. Build it from the post's own front matter and Lab "
            "Overview table rather than inventing facts for it.")
    rows = chr(10).join(
        '      <li><a href="#%s">%s</a></li>' % (sid, name)
        for sid, name in SECTION_ORDER)
    toc = (
        '  <div class="toc">' + chr(10) +
        '    <h3>&#128203; In This Post</h3>' + chr(10) +
        '    <ol>' + chr(10) +
        rows + chr(10) +
        '    </ol>' + chr(10) +
        '  </div>' + chr(10))
    return src["header"].rstrip() + chr(10) + chr(10) + toc


def close_chrome():
    """Closes the jk-post wrapper. Every restructured body must end with it."""
    return chr(10) + "</div>" + chr(10)


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

    # Count ALL divs, not just section divs. The original compared section
    # openings to every closing tag, which was only ever right by accident --
    # it happened to hold while posts had no chrome, and reported a correct
    # post as broken the moment the header and toc came back.
    body_only = out.split("---", 2)[2]
    if body_only.count("<div") != body_only.count("</div>"):
        raise SystemExit("unbalanced <div>: %d open, %d close"
                         % (body_only.count("<div"), body_only.count("</div>")))

    if "<svg" not in out:
        raise SystemExit("architecture diagram (inline <svg>) is missing")

    # THE POST CHROME MUST SURVIVE (added 2026-10-25, after it did not)
    #
    # A post is not only its sections. Above the first <div class="section">
    # sits the jk-post wrapper, the post-header (eyebrow, title, subtitle and
    # the date/tools/cost meta line) and the table of contents.
    #
    # The first ten restructures dropped all three, on every post, because the
    # build replaced the whole body with the nine new sections and extract()
    # only ever captured sections. Every other check here passed: section order,
    # div balance, figures, word count, dates. Jay found it by opening a page on
    # his phone and seeing it start at "Lab Overview" with no index.
    #
    # The table of contents must also be REGENERATED rather than carried over:
    # the old one links to #why, #how, #challenges and friends, which no longer
    # exist after a restructure. A preserved TOC is a menu of dead links.
    for needle, what in (('<div id="jk-post">', "the jk-post wrapper"),
                         ('class="post-header"', "the post-header block"),
                         ('class="post-meta"', "the post-meta line"),
                         ('class="toc"', "the table of contents")):
        if needle not in out:
            raise SystemExit(
                "%s is missing. A restructured post keeps its chrome -- "
                "header and meta verbatim, table of contents regenerated for "
                "the new section ids." % what)

    # EVERY CITED PAGE MUST STILL BE REACHABLE (added 2026-10-29, after it was not)
    #
    # The front matter's `verified_claims:` records which page was checked for
    # each claim, and the badge on the post asserts that work to the reader. A
    # claim is only repeatable if the reader can get to the page, which means the
    # References list has to carry it.
    #
    # Condensing the prose condensed the References list with it, and eleven
    # restructured posts (weeks 13-23) lost at least one cited page. Week 14 lost
    # six, among them the CloudWatch and Athena pricing pages sitting behind nine
    # separate cost claims. Nothing caught it: the shape gate checks headings, not
    # citations, and validate_arch_post.py reports this one as advisory, so the
    # push printed "11 error(s)" and succeeded anyway.
    #
    # This is the cheap place to catch it -- before the file is written, while the
    # old References list is still in src and its wording can be carried over.
    cited = [u.rstrip("/") for u in
             re.findall(r"^\s*source:\s*(https://\S+)", src["fm"], re.M)]
    if cited:
        tail = out.split("References", 1)[-1] if "References" in out else ""
        lost = sorted({u for u in cited if u not in tail.replace("&amp;", "&")})
        if lost:
            raise SystemExit(
                "the References list no longer reaches %d page(s) this post's "
                "verified_claims cite, so the badge asserts a check the reader "
                "cannot repeat:\n  %s\nCarry the entry over from the old "
                "References list rather than dropping it."
                % (len(lost), "\n  ".join(lost)))

    anchors = set(re.findall(r'<a href="#([a-z0-9-]+)"', out))
    dead = sorted(a for a in anchors if 'id="%s"' % a not in out)
    if dead:
        raise SystemExit("table of contents links to sections that do not "
                         "exist: %s" % ", ".join(dead))

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
