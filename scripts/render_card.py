"""
Render a week's LinkedIn architecture card from its HTML source.

Why this exists (2026-08-29): Week 16's card was generated ad hoc and the
source was thrown away. When Jay said it was not sharp, there was nothing to
re-export -- it had to be rebuilt from the image. Cards are now HTML files
committed next to the PNG, and this renders them.

Sharpness comes from the device scale factor, not from the CSS size. The board
is authored at 1200x675 CSS pixels and shot at 2x, so the PNG is 2400x1350 and
stays crisp when a phone renders it at full width. Scaling the CSS up instead
shifts every type metric and reflows the layout.

Usage:
    python scripts/render_card.py week-16-devops-agent-investigations
    python scripts/render_card.py week-16-devops-agent-investigations --scale 3
"""
import argparse
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parents[1]

CARD_W, CARD_H = 1200, 675


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("week", help="week folder name")
    ap.add_argument("--scale", type=int, default=2, help="device scale factor (default 2)")
    ap.add_argument("--name", default="architecture-diagram", help="basename of the .html/.png pair")
    args = ap.parse_args()

    src = REPO / args.week / "docs" / "linkedin" / f"{args.name}.html"
    out = src.with_suffix(".png")
    if not src.exists():
        print(f"no HTML source at {src}", file=sys.stderr)
        return 1

    try:
        from playwright.sync_api import sync_playwright
    except ImportError:
        print("playwright is not installed: pip install playwright && playwright install chromium",
              file=sys.stderr)
        return 1

    with sync_playwright() as p:
        browser = p.chromium.launch()
        page = browser.new_page(
            viewport={"width": CARD_W, "height": CARD_H},
            device_scale_factor=args.scale,
        )
        page.goto(src.as_uri())
        # Web fonts and layout settle a frame or two after load; screenshotting
        # immediately can catch a fallback font at the wrong metrics.
        page.wait_for_timeout(400)
        page.screenshot(path=str(out), clip={"x": 0, "y": 0, "width": CARD_W, "height": CARD_H})
        browser.close()

    try:
        from PIL import Image
        w, h = Image.open(out).size
        print(f"wrote {out.relative_to(REPO)} at {w}x{h} ({args.scale}x)")
        if (w, h) != (CARD_W * args.scale, CARD_H * args.scale):
            print(f"WARNING: expected {CARD_W * args.scale}x{CARD_H * args.scale}", file=sys.stderr)
            return 1
    except ImportError:
        print(f"wrote {out.relative_to(REPO)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
