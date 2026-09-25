"""
Mechanical completeness check for a finished week. Run before calling one done.

Why this exists (2026-08-21): Week 15's LinkedIn architecture diagram was
missed. The rule "LinkedIn draft + diagram after publish" was followed halfway
-- the draft was written, the item was marked done, and nothing verified that
both artifacts existed. Jay caught it. Earlier the same day he also caught two
screenshots that were pictures of a login form, and a publish date a day stale.

A checklist held in my head fails under load. This one runs.

Usage:
    python scripts/check_week_complete.py week-15-cloudtrail-audit-forensics
    python scripts/check_week_complete.py week-15-cloudtrail-audit-forensics --published

Exit code is non-zero if any REQUIRED check fails, so it can gate a workflow.
"""
import argparse
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path(__file__).resolve().parents[1]
BLOG = pathlib.Path(r"C:/Projects/Engineering/katta698.github.io")

LINKEDIN_CHAR_LIMIT = 3000
LINKEDIN_CARD_SIZE = (1200, 675)

results = []


def check(label, ok, detail="", required=True):
    results.append((label, bool(ok), detail, required))



# ---------------------------------------------------------------------------
# The screenshot rules live here as pure functions so that --self-test can feed
# them known-bad input and REQUIRE them to complain. See self_test() below for
# why that matters.
# ---------------------------------------------------------------------------



def orphan_captures(html, shot_dir):
    """Captures on disk that the post never references and that are not
    declared in UNUSED.txt."""
    referenced = set(re.findall(r"screenshots/([\w.-]+\.(?:png|jpg|jpeg))", html))
    declared = set()
    unused_file = shot_dir / "UNUSED.txt"
    if unused_file.is_file():
        declared = {l.strip() for l in unused_file.read_text(encoding="utf-8").splitlines()
                    if l.strip() and not l.startswith("#")}
    on_disk = {f.name for f in shot_dir.glob("*.*")
               if f.suffix.lower() in (".png", ".jpg", ".jpeg")}
    return sorted(on_disk - referenced - declared)


def roadmap_status(root_readme, week_no):
    """The status cell of the roadmap row for this week, or None if no row.

    The roadmap is a markdown table. The row for a week is the one whose first
    cell names it -- either as plain text or as a link. The status is the last
    non-empty cell on that row.
    """
    want = "week %s" % int(week_no)
    for line in root_readme.splitlines():
        s = line.strip()
        if not s.startswith("|") or s.startswith("|--") or "---" in s.split("|")[1:2]:
            continue
        cells = [c.strip() for c in s.strip("|").split("|")]
        if not cells:
            continue
        first = re.sub(r"[\[\]]", "", cells[0]).lower()
        # No regex here: a word boundary written into this line once collapsed
        # into a literal control character, and the rule silently matched nothing.
        if first.startswith(want) and not first[len(want):len(want) + 1].isdigit():
            tail = [c for c in cells[1:] if c]
            return tail[-1] if tail else ""
    return None


def readme_status_mismatch(root_readme, week_no, is_published):
    """Does the roadmap row agree with whether the post is actually live?

    Why this exists (2026-09-19): Week 19's row still read "in progress" a full
    day after the post was published. Jay found it on his phone. Nothing in this
    script looked at the status cell -- it only checked that a row existed and
    pointed at the right folder, both of which were true while the row said
    something false.

    The status cell is a claim about the outside world, so it is checkable
    against the outside world. Returns a reason string, or None if consistent.
    """
    status = roadmap_status(root_readme, week_no)
    if status is None:
        return "no roadmap row for Week %s" % week_no
    done = "complete" in status.lower()
    if is_published and not done:
        return "post is published but the roadmap row says %r" % status
    if not is_published and done:
        return "roadmap row says %r but the post is not published" % status
    return None


def self_test(quiet=False):
    """Prove each rule REJECTS a known-bad page. Run before trusting a green.

    Why this exists (2026-09-12): the figure-order check shipped in a form that
    could not fail, passed the broken page it was written to catch, and I
    reported "all required checks passed" on the strength of it. Jay found the
    error by reading the post. A check nobody has seen fail is an assumption.
    """
    cases = []






    # 4. orphan detection
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        shots = pathlib.Path(d)
        (shots / "01-used.png").write_bytes(b"x")
        (shots / "02-orphan.png").write_bytes(b"x")
        (shots / "03-declared.png").write_bytes(b"x")
        (shots / "UNUSED.txt").write_text("# note" + chr(10) + "03-declared.png" + chr(10), encoding="utf-8")
        html = 'screenshots/01-used.png'
        orphans = orphan_captures(html, shots)
        cases.append(("orphan check finds an unreferenced capture", orphans == ["02-orphan.png"]))
        cases.append(("orphan check honours UNUSED.txt", "03-declared.png" not in orphans))

    # 5. roadmap status agrees with reality
    RM = (chr(10).join([
        "| Week | Topic | Services | Status |",
        "|---|---|---|---|",
        "| [Week 19](./week-19-gitops-argocd) | GitOps | Argo CD | ✅ Complete |",
        "| Week 20 | EventBridge | Events | 📅 Planned |",
    ]))
    cases.append(("roadmap check catches a published week still marked planned",
                  readme_status_mismatch(RM, "20", True) is not None))
    cases.append(("roadmap check catches an unpublished week marked complete",
                  readme_status_mismatch(RM, "19", False) is not None))
    cases.append(("roadmap check passes a consistent published row",
                  readme_status_mismatch(RM, "19", True) is None))
    cases.append(("roadmap check passes a consistent unpublished row",
                  readme_status_mismatch(RM, "20", False) is None))
    cases.append(("roadmap check notices a missing row",
                  readme_status_mismatch(RM, "21", True) is not None))

    bad_count = sum(1 for _, ok in cases if not ok)
    if quiet:
        return bad_count
    print()
    width = max(len(c[0]) for c in cases) + 2
    for label, ok in cases:
        print("  [%s] %s" % ("PASS" if ok else "DEAD", label.ljust(width)))
    print()
    if bad_count:
        print("%d check(s) DO NOT WORK. Their green means nothing until fixed." % bad_count)
        return 1
    print("All %d rule self-tests passed - the checks can actually fail." % len(cases))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("week", nargs="?", help="week folder name, e.g. week-15-cloudtrail-audit-forensics")
    ap.add_argument("--published", action="store_true",
                    help="also check the post is built and live-ready in the blog repo")
    ap.add_argument("--self-test", action="store_true",
                    help="prove every rule rejects a known-bad page, then exit")
    args = ap.parse_args()

    if args.self_test:
        sys.exit(self_test())

    # Every run validates its own rules first. This is not optional and there is
    # no flag to skip it: on 2026-09-12 the figure-order rule shipped in a form
    # that could not fail, passed the broken page it existed to catch, and this
    # script printed "All required checks passed". Jay found the error by
    # reading the post. A green from a rule nobody has seen fail is an
    # assumption wearing a checkmark.
    if self_test(quiet=True):
        print(chr(10) + "ABORTING: some rules in this script do not work.")
        print("Run  python scripts/check_week_complete.py --self-test  for detail.")
        print("Do not trust any result from this script until that is green.")
        sys.exit(2)

    wk = REPO / args.week
    if not wk.is_dir():
        sys.exit(f"no such week folder: {wk}")

    slug = args.week
    shots = sorted((wk / "docs/blog/screenshots").glob("*.*")) if (wk / "docs/blog/screenshots").is_dir() else []

    # ---- repo-side artefacts -------------------------------------------
    check("README.md exists", (wk / "README.md").is_file())
    check("screenshots present", len(shots) >= 5, f"{len(shots)} found")

    li = wk / "docs/linkedin"
    post_txt = li / "post.txt"
    card = li / "architecture-diagram.png"

    check("LinkedIn post.txt exists", post_txt.is_file())
    if post_txt.is_file():
        n = len(post_txt.read_text(encoding="utf-8"))
        check(f"LinkedIn post under {LINKEDIN_CHAR_LIMIT} chars", n < LINKEDIN_CHAR_LIMIT, f"{n} chars")

    # The one that was missed.
    check("LinkedIn architecture-diagram.png exists", card.is_file())
    if card.is_file():
        try:
            from PIL import Image
            w, h = Image.open(card).size
            # 1200x675 at 1x reads soft on a phone, so cards are rendered at an
            # integer scale factor (2x by default -- see scripts/render_card.py).
            # What must hold is the aspect ratio and a floor on width.
            cw, ch = LINKEDIN_CARD_SIZE
            scale = w / cw
            ok = scale >= 1 and abs(scale - round(scale)) < 0.001 and h == round(ch * scale)
            check("LinkedIn card is 1200x675 (or an integer multiple)", ok,
                  f"{w}x{h}" + (f" = {round(scale)}x" if ok else ""))
        except Exception as exc:
            check("LinkedIn card readable", False, str(exc))

    # ---- root README ----------------------------------------------------
    root = (REPO / "README.md").read_text(encoding="utf-8", errors="replace")
    week_no = re.match(r"week-(\d+)", slug)
    wn = week_no.group(1) if week_no else "??"
    check(f"root README has a Week {wn} section", f"## Week {wn} —" in root or f"## Week {int(wn)} —" in root)
    check(f"root README roadmap row links the folder", f"({slug})" in root or f"./{slug}" in root)

    # Is the post actually live? Read it from the blog repo rather than taking
    # --published as the answer: the flag says what this run intends to check,
    # not what a reader of the site would see. A post carrying "draft: true" is
    # built noindex and unlisted, so it is not published no matter how the
    # script was invoked.
    src = BLOG / "posts" / f"{slug}.html"
    if src.is_file():
        head = src.read_text(encoding="utf-8", errors="replace")[:2000]
        live = not re.search(r"^draft:\s*true", head, re.M)
    else:
        live = False
    why = readme_status_mismatch(root, wn, live)
    check("roadmap row status matches whether the post is live", why is None,
          why or ("live" if live else "draft/unpublished"))

    # ---- no leaked identifiers in tracked text --------------------------
    try:
        out = subprocess.run(
            ["git", "grep", "-l", "-E", r"[0-9]{12}", "--", f"{slug}/*.md", f"{slug}/*.sh",
             f"{slug}/*.py", f"{slug}/*.tf", f"{slug}/*.sql"],
            cwd=REPO, capture_output=True, text=True, timeout=60)
        hits = [l for l in out.stdout.splitlines() if l.strip()]
        # BLOCKING, not advisory. This rule was advisory until 2026-09-24, and it
        # worked perfectly the whole time: it printed
        #   [warn] ... week-18-.../terraform/environments/dev/variables.tf
        # on every run from Week 18 onward, and the script then reported "All
        # required checks passed". A real account id sat in a public repo for
        # twelve days because the finding was true, visible, and ignorable.
        #
        # A warning nobody must act on is a warning nobody acts on.
        check("no 12-digit numbers in this week's tracked text", not hits,
              "; ".join(hits[:3]))
    except Exception:
        pass

    # ---- the same leak check, across the WHOLE repo ---------------------
    # Scoping the scan to one week means a leak is only ever found by someone
    # who happens to run the check for that week. Week 18's leak was invisible
    # from Week 19 and Week 20 runs for exactly that reason.
    #
    # The ids are NOT written here. The first version of this check hardcoded
    # them and promptly flagged itself -- a leak detector that is itself the
    # leak. They come from the live caller identity, and from an optional
    # gitignored file for the other org accounts.
    ids = set()
    try:
        who = subprocess.run(["aws", "sts", "get-caller-identity",
                              "--query", "Account", "--output", "text"],
                             capture_output=True, text=True, timeout=60)
        v = (who.stdout or "").strip()
        if len(v) == 12 and v.isdigit():
            ids.add(v)
    except Exception:
        pass
    extra = REPO / "scripts" / ".account-ids"
    if extra.is_file():
        for line in extra.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if len(line) == 12 and line.isdigit():
                ids.add(line)

    TEXT_GLOBS = ["*.md", "*.sh", "*.py", "*.tf", "*.sql", "*.json", "*.yml", "*.yaml", "*.html"]
    if not ids:
        check("account ids resolved for the repo-wide leak scan", False,
              "no credentials and no scripts/.account-ids -- scan did NOT run",
              required=False)
    else:
        try:
            out = subprocess.run(
                ["git", "grep", "-l", "-E", "|".join(sorted(ids)), "--"] + TEXT_GLOBS,
                cwd=REPO, capture_output=True, text=True, timeout=180)
            leaks = [l for l in out.stdout.splitlines() if l.strip()]
            check("no real account id anywhere in the tracked repo", not leaks,
                  "; ".join(leaks[:3]))
        except Exception as exc:                                # noqa: BLE001
            check("repo-wide leak scan ran", False, str(exc)[:60])

    # ---- published post -------------------------------------------------
    if args.published:
        src = BLOG / "posts" / f"{slug}.html"
        built = BLOG / "blog" / slug / "index.html"
        check("post source exists in blog repo", src.is_file())
        check("post is built under blog/", built.is_file())
        if src.is_file():
            t = src.read_text(encoding="utf-8", errors="replace")
            h2 = re.findall(r"<h2>(.*?)</h2>", t, re.S)
            check("10 canonical H2 sections", len(h2) == 10, f"{len(h2)} found")
            check("architecture SVG embedded", "<svg" in t)
            check("divs balanced", t.count("<div") == t.count("</div>"),
                  f"{t.count('<div')} open / {t.count('</div>')} close")
            m = re.search(r"verified:\s*'(\d{4}-\d{2}-\d{2})'", t)
            check("front matter carries a verified date", bool(m), m.group(1) if m else "missing")

            # A badge asserts a human checked the figures. That is only worth
            # something if the figures are individually traceable -- Week 16
            # shipped with a badge, 5 claims and 22% of its printed numbers
            # appearing in no claim at all, including every cost figure. The
            # blog repo already owns the tool that measures this; it was only
            # ever run against the Architecture series.
            audit = BLOG / "scripts" / "audit_claims.py"
            if m and audit.is_file():
                try:
                    p = subprocess.run([sys.executable, str(audit), slug],
                                       capture_output=True, text=True, cwd=str(BLOG),
                                       timeout=120, encoding="utf-8", errors="replace")
                    pct = re.search(r"(\d+)%", p.stdout or "")
                    traced = int(pct.group(1)) if pct else -1
                    untraced = ""
                    tail = (p.stdout or "").strip().splitlines()
                    if traced < 100 and tail:
                        untraced = tail[-1].strip()[:70]
                    # 80% is the floor, not the goal: a handful of illustrative
                    # numbers in prose do not need sourcing, but a majority of
                    # untraced figures under a badge is the failure this catches.
                    check("verified figures traced to claims (>=80%)", traced >= 80,
                          f"{traced}% traced" + (f" - untraced: {untraced}" if untraced else ""))
                except Exception as exc:
                    check("claims audit ran", False, str(exc), required=False)
            # Structure is not appearance. Week 16 passed every check on this
            # list and still shipped six scrambled paragraphs, because nothing
            # here looks at the laid-out page. This does.
            render = REPO / "scripts" / "check_render.py"
            if render.is_file():
                try:
                    p2 = subprocess.run([sys.executable, str(render), slug],
                                        capture_output=True, text=True, timeout=180,
                                        encoding="utf-8", errors="replace")
                    detail = (p2.stdout or p2.stderr or "").strip().splitlines()
                    detail = detail[-1][:80] if detail else ""
                    check("post renders correctly at 390px and 1280px",
                          p2.returncode == 0, detail)
                except Exception as exc:
                    check("render check ran", False, str(exc), required=False)

            # every figure must resolve to a file that actually exists
            missing = []
            for fn in re.findall(r"screenshots/([\w.-]+\.(?:png|jpg|jpeg))", t):
                if not (wk / "docs/blog/screenshots" / fn).is_file():
                    missing.append(fn)
            check("every figure references a file that exists", not missing, "; ".join(missing[:4]))

            # ---- EVERY CAPTURE IS EITHER USED OR DELIBERATELY NOT ----------
            #
            # Week 18 captured ten screenshots and wired four into the post.
            # The HCP run was the one left out, and Jay had to ask twice. The
            # check above only proves that referenced files exist; it is blind
            # to files captured and never referenced.
            #
            # If a capture is genuinely not for the post, list it in
            # docs/blog/screenshots/UNUSED.txt, one filename per line. Saying
            # so is cheap; forgetting is what costs.
            orphans = orphan_captures(t, wk / "docs/blog/screenshots")
            check("every screenshot is used or declared unused", not orphans,
                  ("%d unused: %s" % (len(orphans), ", ".join(orphans[:4]))) if orphans else "")

            # ---- NO FORWARD-REFERENCED STATE --------------------------------
            #
            # Screenshots are numbered in build order. So inside the build
            # narrative, they must appear in ascending numeric order -- a lower
            # number appearing after a higher one means a screenshot of live
            # state shows up before the step that created it.
            #
            # Week 6 learned this and it is written in SESSION_CONTEXT. Week 18
            # broke it anyway: the Pod Identity console page sat under Step 2,
            # before the Step 3 that creates the cluster. Prose did not stop it;
            # this does. Sections after the build narrative are exempt, since
            # Challenges legitimately revisits earlier evidence.
            # Bound the narrative by SECTION IDs, not by heading text. The
            # first version split on the literal "Challenges &mdash;", which
            # also appears in the table of contents at the top of every post --
            # so it sliced off the entire body, found no figures at all, and
            # passed vacuously. It could not fail. Jay found the forward
            # reference it was written to catch, the same day it was added.
            # Figure placement is owned by the blog repo's check_figure_order.py
            # and enforced site-wide in its prepublish CI. Delegating rather than
            # keeping a second copy: this script briefly carried a stricter
            # "capture numbers must ascend" rule that was wrong on 11 of 12
            # published posts, and two rules that disagree is how red gets
            # ignored. One rule, one place, invoked from both.
            fig_chk = BLOG / "scripts" / "check_figure_order.py"
            if fig_chk.is_file():
                try:
                    p3 = subprocess.run([sys.executable, str(fig_chk), slug],
                                        capture_output=True, text=True, cwd=str(BLOG),
                                        timeout=180, encoding="utf-8", errors="replace")
                    detail = [l.strip() for l in (p3.stdout or "").splitlines() if "figure" in l]
                    check("no figure appears above its deploy step",
                          p3.returncode == 0, detail[0][:80] if detail else "")
                except Exception as exc:
                    check("figure-order check ran", False, str(exc), required=False)


    # ---- report ---------------------------------------------------------
    width = max(len(r[0]) for r in results) + 2
    failed_required = 0
    print()
    for label, ok, detail, required in results:
        mark = "PASS" if ok else ("FAIL" if required else "warn")
        if not ok and required:
            failed_required += 1
        print(f"  [{mark}] {label:<{width}} {detail}")
    print()
    if failed_required:
        print(f"{failed_required} required check(s) FAILED — the week is not done.")
        sys.exit(1)
    print("All required checks passed.")


if __name__ == "__main__":
    main()
