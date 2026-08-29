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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("week", help="week folder name, e.g. week-15-cloudtrail-audit-forensics")
    ap.add_argument("--published", action="store_true",
                    help="also check the post is built and live-ready in the blog repo")
    args = ap.parse_args()

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

    # ---- no leaked identifiers in tracked text --------------------------
    try:
        out = subprocess.run(
            ["git", "grep", "-l", "-E", r"[0-9]{12}", "--", f"{slug}/*.md", f"{slug}/*.sh",
             f"{slug}/*.py", f"{slug}/*.tf", f"{slug}/*.sql"],
            cwd=REPO, capture_output=True, text=True, timeout=60)
        hits = [l for l in out.stdout.splitlines() if l.strip()]
        check("no 12-digit numbers in this week's tracked text", not hits, "; ".join(hits[:3]), required=False)
    except Exception:
        pass

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
            # every figure must resolve to a file that actually exists
            missing = []
            for fn in re.findall(r"screenshots/([\w.-]+\.(?:png|jpg|jpeg))", t):
                if not (wk / "docs/blog/screenshots" / fn).is_file():
                    missing.append(fn)
            check("every figure references a file that exists", not missing, "; ".join(missing[:4]))

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
