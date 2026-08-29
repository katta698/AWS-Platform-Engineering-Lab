"""
Render a published week's post in a real browser and check it actually looks right.

Why this exists (2026-08-29): Week 16 shipped with six .flow-step blocks whose
sentences rendered as scrambled columns -- unreadable on a phone, wrong on
desktop -- and every structural check passed. check_week_complete.py counts H2s,
balances divs and resolves figures. None of that looks at the page. Jay found it
on his phone eight hours after publish.

The specific bug: .flow-step is display:flex, built for an icon beside a content
block. A bare sentence inside it makes every inline element (strong, em, code)
its own flex column. Nothing in the HTML is malformed, so nothing textual can
catch it -- it is only visible once laid out.

Checks, at 390px (phone) and 1280px (desktop):
  1. no flex .flow-step without a .flow-icon child   <- the Week 16 bug exactly
  2. no horizontal overflow of the document
  3. no element wider than the viewport (reports the offenders)

Screenshots are written alongside so a human can still look, because these three
checks are the failures we know about, not the ones we do not.

Usage:
    python scripts/check_render.py week-16-devops-agent-investigations
    python scripts/check_render.py week-16-devops-agent-investigations --keep-shots
"""
import argparse
import contextlib
import functools
import http.server
import pathlib
import socket
import socketserver
import sys
import tempfile
import threading

BLOG = pathlib.Path(r"C:/Projects/Engineering/katta698.github.io")
WIDTHS = [("phone", 390), ("desktop", 1280)]

# A code block scrolling inside its own box is intentional; the document
# scrolling sideways is not.
OVERFLOW_TOLERANCE_PX = 2


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


@contextlib.contextmanager
def serve(root):
    port = free_port()
    handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root))

    class QuietHandler(handler.func):
        def log_message(self, *a):
            pass

    handler = functools.partial(QuietHandler, directory=str(root))

    class Quiet(socketserver.TCPServer):
        allow_reuse_address = True

        def handle_error(self, *a):
            pass

    httpd = Quiet(("127.0.0.1", port), handler)
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    try:
        yield port
    finally:
        httpd.shutdown()
        httpd.server_close()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("week", help="week folder name, e.g. week-16-devops-agent-investigations")
    ap.add_argument("--keep-shots", action="store_true", help="print screenshot paths and keep them")
    args = ap.parse_args()

    built = BLOG / "blog" / args.week / "index.html"
    if not built.is_file():
        print(f"no built page at {built} -- run sync_blog.py first", file=sys.stderr)
        return 1

    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("playwright not installed: pip install playwright && playwright install chromium",
              file=sys.stderr)
        return 1

    outdir = pathlib.Path(tempfile.gettempdir()) / f"render-{args.week}"
    outdir.mkdir(exist_ok=True)
    failures = []

    with serve(BLOG) as port, sync_playwright() as p:
        browser = p.chromium.launch()
        url = f"http://127.0.0.1:{port}/blog/{args.week}/"
        for name, width in WIDTHS:
            page = browser.new_page(viewport={"width": width, "height": 900})
            page.goto(url, wait_until="load")
            page.wait_for_timeout(500)

            # A sentence inside a flex or grid container. Each inline element
            # (strong, em, code, a) becomes its own track, so the words lay out
            # in columns and the reading order breaks -- worst on a narrow
            # screen, where every column wraps independently. This is the
            # general form of the Week 16 bug; checking .flow-step by name would
            # only catch it in the one place it already happened.
            scrambled = page.evaluate("""() => {
                const INLINE = new Set(['STRONG','EM','CODE','A','SPAN','B','I','SMALL']);
                const out = [];
                document.querySelectorAll('#jk-post *').forEach(el => {
                    const d = getComputedStyle(el).display;
                    if (d !== 'flex' && d !== 'grid') return;
                    let text = 0, inline = 0;
                    el.childNodes.forEach(n => {
                        if (n.nodeType === 3 && n.textContent.trim().length > 3) text++;
                        else if (n.nodeType === 1 && INLINE.has(n.tagName)) inline++;
                    });
                    if (text && inline) {
                        out.push((el.tagName + '.' + (el.className || '')).slice(0, 50));
                    }
                });
                return [...new Set(out)];
            }""")
            if scrambled:
                failures.append(f"{name}: prose inside a flex/grid container -- inline elements "
                                f"become columns and the words lay out in the wrong order: "
                                f"{scrambled[:4]}")

            overflow = page.evaluate("""(tol) => {
                const d = document.documentElement;
                return d.scrollWidth - d.clientWidth > tol
                    ? {by: d.scrollWidth - d.clientWidth} : null;
            }""", OVERFLOW_TOLERANCE_PX)
            if overflow:
                wide = page.evaluate("""(w) => {
                    const out = [];
                    document.querySelectorAll('#jk-post *').forEach(el => {
                        if (el.getBoundingClientRect().width > w + 2) {
                            out.push((el.tagName + '.' + (el.className || '')).slice(0, 60));
                        }
                    });
                    return [...new Set(out)].slice(0, 5);
                }""", width)
                failures.append(f"{name}: document scrolls sideways by {overflow['by']}px "
                                f"-- widest: {wide}")

            shot = outdir / f"{name}.png"
            page.screenshot(path=str(shot), full_page=False)
            if args.keep_shots:
                print(f"  {name} ({width}px): {shot}")
            page.close()
        browser.close()

    if failures:
        print("\nRENDER CHECK FAILED")
        for f in failures:
            print(f"  - {f}")
        print(f"\n  screenshots: {outdir}")
        return 1
    print(f"render OK at {', '.join(f'{w}px' for _, w in WIDTHS)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
