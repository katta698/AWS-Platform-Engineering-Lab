"""
Render a block of text as a PNG, for evidence a console screenshot cannot show.

Some proofs are not console pages. An IAM policy document read back from the
API is stronger evidence than a console rendering of it, and a terminal session
showing a 403 followed by a signed 200 is not a page at all. Week 13 shipped a
rendered side-by-side for the same reason.

Also: chasing a console SPA into the right expanded panel is how a
convincingly-wrong screenshot gets saved. If the API can produce the fact
directly, render the fact.

    python scripts/render_evidence.py out.png --title "..." --file body.txt
    some-command | python scripts/render_evidence.py out.png --title "..."

Renders at 2x so the type stays sharp when the blog scales it down.
"""
import argparse
import html
import pathlib
import sys
import tempfile

TEMPLATE = """<!doctype html><meta charset="utf-8">
<style>
  * { box-sizing: border-box }
  body { margin: 0; background: #fff;
         font-family: "Segoe UI", -apple-system, Arial, sans-serif; }
  .wrap { width: %(width)spx; padding: 22px 26px; }
  .title { font-size: 15px; font-weight: 600; color: #16191f; margin-bottom: 4px; }
  .sub   { font-size: 12.5px; color: #6c757d; margin-bottom: 14px; }
  pre {
    margin: 0; background: #1e293b; color: #e2e8f0; border-radius: 6px;
    padding: 16px 18px; font-family: "Cascadia Mono", Consolas, monospace;
    font-size: %(font)spx; line-height: 1.5; white-space: pre; overflow: visible;
  }
  .ok   { color: #4ade80 }
  .bad  { color: #f87171 }
  .dim  { color: #94a3b8 }
  .key  { color: #fbbf24 }
</style>
<div class="wrap">
  <div class="title">%(title)s</div>
  %(subtitle)s
  <pre>%(body)s</pre>
</div>
"""


def colourise(text):
    """Light touch only -- enough to make a verdict readable at a glance."""
    out = []
    for line in html.escape(text).split("\n"):
        cls = ""
        low = line.lower()
        if "403" in line or "denied" in low or "error" in low or "not clean" in low:
            cls = "bad"
        elif ("200" in line or "true" in low or "connected" in low
              or "[gone]" in low or "clean" in low or "ok" in low):
            cls = "ok"
        elif line.strip().startswith("#") or line.strip().startswith("$"):
            cls = "dim"
        out.append('<span class="%s">%s</span>' % (cls, line) if cls else line)
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("output")
    ap.add_argument("--title", required=True)
    ap.add_argument("--subtitle", default="")
    ap.add_argument("--file", default=None, help="read body from a file instead of stdin")
    ap.add_argument("--width", type=int, default=1000)
    ap.add_argument("--font", type=float, default=12.5)
    ap.add_argument("--scale", type=int, default=2)
    ap.add_argument("--wrap", type=int, default=0,
                    help="hard-wrap prose at N columns; 0 leaves lines untouched. "
                         "Terminal output is fine unwrapped, but a model's prose "
                         "runs off the right edge because <pre> does not wrap.")
    args = ap.parse_args()

    body = (pathlib.Path(args.file).read_text(encoding="utf-8")
            if args.file else sys.stdin.read())

    if args.wrap:
        import textwrap
        wrapped = []
        for line in body.splitlines():
            if len(line) <= args.wrap:
                wrapped.append(line)
            else:
                indent = ' ' * (len(line) - len(line.lstrip()))
                wrapped.extend(textwrap.wrap(line, args.wrap,
                                             subsequent_indent=indent) or [''])
        body = chr(10).join(wrapped)

    page = TEMPLATE % {
        "width": args.width, "font": args.font,
        "title": html.escape(args.title),
        "subtitle": ('<div class="sub">%s</div>' % html.escape(args.subtitle)
                     if args.subtitle else ""),
        "body": colourise(body.rstrip("\n")),
    }

    tmp = pathlib.Path(tempfile.gettempdir()) / "evidence.html"
    tmp.write_text(page, encoding="utf-8")

    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": args.width, "height": 400},
                        device_scale_factor=args.scale)
        pg.goto(tmp.as_uri())
        pg.wait_for_timeout(250)
        pg.locator(".wrap").screenshot(path=args.output)
        b.close()
    print("wrote", args.output)


if __name__ == "__main__":
    main()
