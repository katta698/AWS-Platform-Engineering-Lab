#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Blank the signed-in name from the AWS console badge in committed screenshots.

    python scripts/redact_console_identity.py --dry-run
    python scripts/redact_console_identity.py --apply
    python scripts/redact_console_identity.py --self-test

Why this exists (2026-10-05)
----------------------------
Every AWS console screenshot renders the signed-in identity in a badge at the
top right: "<display name> (<account id>)". capture.py has redacted the account
ID since it was written, and never redacted the NAME -- because nobody looked
at that corner of the frame. On this account the display name is the local part
of a personal email address, and it is in every console screenshot of every
published week. The blog serves those images straight from the lab repos over
raw.githubusercontent.com, so they are public.

capture.py now redacts the badge at capture time. This fixes what is already
committed.

HOW IT FINDS THE BADGE
    The badge is painted in a single flat teal (64, 191, 169) that appears
    nowhere else in the console chrome. Find that colour in the top strip of the
    image, take its bounding box, repaint it, and write "<user> (<account-id>)"
    back in its place. No OCR, no hardcoded personal string -- which matters,
    because hardcoding the name to search for it would put the name in this
    committed file.

WHAT IT DOES NOT TOUCH
    The line under the badge reads "<Role>/<role-session-name>", which on this
    account is the owner's public GitHub handle -- the same string that appears
    in every repository URL. It is not a personal identifier in the way the
    display name is, and repainting dark-on-dark text without OCR is guesswork.
"""
import argparse
import os
import sys

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

BADGE_RGB = (64, 191, 169)
TOLERANCE = 12
# The badge lives in the header. Search generously but never the whole frame.
TOP_STRIP_PX = 60
RIGHT_FRACTION = 0.55
TEXT_RGB = (22, 29, 38)
REPLACEMENT = "<user> (<account-id>)"

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\segoeui.ttf",
    r"C:\Windows\Fonts\arial.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
]


def close_to(pixel, target=BADGE_RGB, tol=TOLERANCE):
    """True when a pixel is the badge teal within tolerance. Pure, for tests."""
    return all(abs(int(pixel[i]) - target[i]) <= tol for i in range(3))


def badge_box(im, min_column_height=8):
    """Bounding box of the identity badge, or None.

    The console also paints a 1-2px teal account stripe across the FULL width
    of the header. Taking the bounding box of every teal pixel therefore spans
    from the far left to the badge, and repainting that rectangle would erase
    the region selector and the header icons -- caught before this ever wrote a
    file, by cropping a Week 20 screenshot and looking at it.

    So: keep only columns that are teal for at least `min_column_height` rows.
    The stripe is one or two rows tall; the badge is about twenty.
    """
    w, h = im.size
    px = im.load()
    strip = min(TOP_STRIP_PX, h)
    x_start = int(w * RIGHT_FRACTION)

    cols = {}
    for x in range(x_start, w):
        rows = [y for y in range(strip) if close_to(px[x, y])]
        if len(rows) >= min_column_height:
            cols[x] = rows
    if not cols:
        return None

    xs = sorted(cols)
    # The badge is contiguous; take the right-most run so a stray tall teal
    # element further left cannot widen the box.
    run = [xs[-1]]
    for x in reversed(xs[:-1]):
        if run[-1] - x <= 3:
            run.append(x)
        else:
            break
    x0, x1 = min(run), max(run)
    ys = [y for x in run for y in cols[x]]
    y0, y1 = min(ys), max(ys)

    if (x1 - x0) < 80 or (y1 - y0) < 8:
        return None
    return (x0, y0, x1 + 1, y1 + 1)


def load_font(size):
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except Exception:
                pass
    return ImageFont.load_default()


def redact(path, apply=False):
    """Returns (changed, reason)."""
    im = Image.open(path)
    if im.mode != "RGB":
        im = im.convert("RGB")
    box = badge_box(im)
    if box is None:
        return False, "no badge"

    x0, y0, x1, y1 = box
    draw = ImageDraw.Draw(im)
    draw.rectangle([x0, y0, x1 - 1, y1 - 1], fill=BADGE_RGB)

    height = y1 - y0
    font = load_font(max(10, int(height * 0.62)))
    tw = draw.textlength(REPLACEMENT, font=font)
    # Right-aligned like the original, leaving room for the dropdown caret.
    tx = max(x0 + 4, x1 - 18 - tw)
    ty = y0 + max(0, (height - int(height * 0.62) - 2) // 2)
    draw.text((tx, ty), REPLACEMENT, fill=TEXT_RGB, font=font)

    if apply:
        im.save(path)
    return True, "badge at %s" % (box,)


def self_test():
    cases = []
    cases.append(("exact badge teal matches", close_to((64, 191, 169))))
    cases.append(("near teal within tolerance matches", close_to((59, 191, 169))))
    cases.append(("console dark header does not match", not close_to((22, 29, 38))))
    cases.append(("white page body does not match", not close_to((255, 255, 255))))
    cases.append(("darker teal outside tolerance does not match",
                  not close_to((9, 111, 100))))

    # A synthetic frame: teal ribbon top-right, plus a teal blob in the body
    # that must NOT be picked up.
    im = Image.new("RGB", (600, 400), (255, 255, 255))
    d = ImageDraw.Draw(im)
    d.rectangle([420, 4, 580, 24], fill=BADGE_RGB)      # the badge
    d.rectangle([40, 200, 300, 260], fill=BADGE_RGB)    # page content, same colour
    # The full-width 1px account stripe that broke the first attempt.
    d.rectangle([0, 0, 599, 1], fill=BADGE_RGB)
    box = badge_box(im)
    cases.append(("finds the badge in the top strip", box is not None))
    cases.append(("the full-width 1px account stripe does not widen the box",
                  box is not None and box[0] >= 400)),
    cases.append(("ignores same-coloured content lower in the page",
                  box is not None and box[1] < TOP_STRIP_PX and box[3] < TOP_STRIP_PX))
    cases.append(("box is on the right half",
                  box is not None and box[0] >= 600 * RIGHT_FRACTION))

    # A frame with no badge at all.
    plain = Image.new("RGB", (600, 400), (255, 255, 255))
    cases.append(("a frame with no badge returns None", badge_box(plain) is None))

    # A narrow teal speck in the strip is not a badge.
    speck = Image.new("RGB", (600, 400), (255, 255, 255))
    ImageDraw.Draw(speck).rectangle([560, 4, 575, 20], fill=BADGE_RGB)
    cases.append(("a narrow speck is not mistaken for a badge",
                  badge_box(speck) is None))

    bad = 0
    for label, ok in cases:
        print("  [%s] %s" % ("PASS" if ok else "DEAD", label))
        bad += not ok
    print()
    if bad:
        print("%d case(s) DO NOT WORK." % bad)
        return 1
    print("All %d badge-detection cases pass." % len(cases))
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--self-test", action="store_true")
    ap.add_argument("--root", default=REPO, help="repository root to sweep")
    args = ap.parse_args()

    if args.self_test:
        return self_test()
    if not (args.apply or args.dry_run):
        print("pass --dry-run or --apply")
        return 2

    targets = []
    for dirpath, _, files in os.walk(args.root):
        if ".git" in dirpath.split(os.sep):
            continue
        if "screenshots" not in dirpath.replace("\\", "/").split("/"):
            continue
        for f in files:
            if f.lower().endswith(".png"):
                targets.append(os.path.join(dirpath, f))

    changed = skipped = 0
    for p in sorted(targets):
        try:
            did, why = redact(p, apply=args.apply)
        except Exception as e:
            print("  ERROR %s: %s" % (os.path.relpath(p, args.root), e))
            continue
        if did:
            changed += 1
            print("  %s %s" % ("redacted" if args.apply else "would redact",
                               os.path.relpath(p, args.root)))
        else:
            skipped += 1

    print()
    print("  %d image(s) with a console badge, %d without" % (changed, skipped))
    print("  %d scanned under %s" % (len(targets), args.root))
    if not args.apply:
        print("  dry run -- nothing written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
