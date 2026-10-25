#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Photograph a REAL terminal running REAL commands.

    python scripts/screenshots/capture_terminal.py <commands.sh> <output.png>

WHY THIS EXISTS (2026-10-25)
----------------------------
Jay asked where the AWS CLI figures were taken, and the honest answer was that
three of them were not taken anywhere: they were typeset by
render_terminal_card.py from a committed .card file, styled to look like a
terminal. The data in them was real, but the command lines had been retyped and
trimmed for width, and no terminal was photographed.

His instruction, for every cloud lab from here on: real terminal screenshots
when possible.

HOW THIS KEEPS ITSELF HONEST
----------------------------
1. The commands are echoed BY BASH, not by me. The script runs under `set -x`
   with PS4='$ ', so each line on screen is printed by the shell from the
   command it is actually about to execute. I cannot quietly show one command
   and run another -- the only way to change what appears is to change what
   runs.

2. The window is a real mintty, rendering with a real terminal's font and
   wrapping. The PNG is a Win32 capture of that window.

3. The commands run TWICE. The first run is headless and its text is scanned
   for the account ID, the signed-in username and anything shaped like a
   credential. If that scan trips, nothing is captured at all -- which is
   stronger than redacting a picture afterwards, because text can be searched
   and pixels cannot.

   This ordering is the point. capture.py learned the same lesson the hard way:
   a redactor only removes what you thought to list. Here the gate runs against
   the real output before a window ever opens.

4. The .sh is committed next to the figure, the same discipline the .card files
   introduced after Week 16: a figure whose source is gone is a claim you can
   no longer check or correct.

WHAT IT DOES NOT DO
-------------------
It does not fake a prompt for commands that were never run, and it does not
accept pre-written output. If a figure needs output from a resource that no
longer exists, that figure cannot be a terminal capture, and a card -- clearly
declared as one in FIGURE_PLAN.md -- is the honest fallback.
"""
from __future__ import annotations

import argparse
import ctypes
import os
import re
import subprocess
import sys
import tempfile
import time
from ctypes import wintypes
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

GIT_BASH = r"C:\Program Files\Git\bin\bash.exe"
MINTTY = r"C:\Program Files\Git\usr\bin\mintty.exe"

# Anything matching these must never reach a frame. Mirrors capture.py's list.
SECRET_PATTERNS = [
    ("AWS account ID", re.compile(r"\b\d{12}\b")),
    ("access key", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("secret-looking literal", re.compile(r"(?i)\b(?:secret|password|token)\s*[=:]\s*\S{12,}")),
    ("personal email", re.compile(r"[A-Za-z0-9._%+-]+@(?:gmail|outlook|yahoo)\.com", re.I)),
    ("home path", re.compile(r"(?i)[A-Z]:\\\\Users\\\\[^\\\\\s]+")),
]


def run_headless(script: Path, extra_env: dict | None = None) -> tuple[int, str]:
    """Run the commands once, capturing text, so the output can be scanned."""
    env = dict(os.environ, PS4="$ ", **(extra_env or {}))
    p = subprocess.run(
        [GIT_BASH, "--noprofile", "--norc", "-c", f'set -x; source "{script.as_posix()}"'],
        capture_output=True, text=True, env=env, encoding="utf-8", errors="replace")
    return p.returncode, (p.stdout or "") + (p.stderr or "")


def scan(text: str, extra: list[str]) -> list[str]:
    hits = []
    for label, pat in SECRET_PATTERNS:
        for m in set(pat.findall(text)):
            hits.append(f"{label}: {m}")
    for e in extra:
        if e and e.lower() in text.lower():
            hits.append(f"caller-supplied: {e}")
    return hits


# ---------------------------------------------------------------- win32 capture
user32 = ctypes.windll.user32
gdi32 = ctypes.windll.gdi32
user32.SetProcessDPIAware()


def find_window(title: str, timeout: float = 60.0):
    """Match the title by PREFIX.

    mintty pads its window title with non-breaking spaces (U+00A0), so an exact
    FindWindowW never matches and the capture fails with "could not find the
    terminal window" while the terminal is sitting there in plain sight.
    """
    deadline = time.time() + timeout
    while time.time() < deadline:
        found = []

        @ctypes.WINFUNCTYPE(ctypes.c_bool, wintypes.HWND, wintypes.LPARAM)
        def cb(h, _l):
            n = user32.GetWindowTextLengthW(h)
            if n:
                b = ctypes.create_unicode_buffer(n + 1)
                user32.GetWindowTextW(h, b, n + 1)
                if b.value.replace(chr(160), " ").strip() == title:
                    found.append(h)
            return True

        user32.EnumWindows(cb, 0)
        if found:
            return found[0]
        time.sleep(0.3)
    return None


def capture_window(hwnd, out: Path) -> tuple[int, int]:
    """Capture a window by its own device context.

    PrintWindow with PW_RENDERFULLCONTENT renders the window's full client area
    even where it falls outside the visible desktop, which matters here: the
    display is 540px wide and a readable CLI figure is not.
    """
    rect = wintypes.RECT()
    user32.GetWindowRect(hwnd, ctypes.byref(rect))
    w, h = rect.right - rect.left, rect.bottom - rect.top
    if w <= 0 or h <= 0:
        raise SystemExit("window has no size")

    hdc = user32.GetWindowDC(hwnd)
    mem = gdi32.CreateCompatibleDC(hdc)
    bmp = gdi32.CreateCompatibleBitmap(hdc, w, h)
    gdi32.SelectObject(mem, bmp)
    if not user32.PrintWindow(hwnd, mem, 2):   # 2 = PW_RENDERFULLCONTENT
        user32.PrintWindow(hwnd, mem, 0)

    from PIL import Image
    class BMI(ctypes.Structure):
        _fields_ = [("biSize", wintypes.DWORD), ("biWidth", wintypes.LONG),
                    ("biHeight", wintypes.LONG), ("biPlanes", wintypes.WORD),
                    ("biBitCount", wintypes.WORD), ("biCompression", wintypes.DWORD),
                    ("biSizeImage", wintypes.DWORD), ("biXPelsPerMeter", wintypes.LONG),
                    ("biYPelsPerMeter", wintypes.LONG), ("biClrUsed", wintypes.DWORD),
                    ("biClrImportant", wintypes.DWORD)]
    bi = BMI()
    bi.biSize = ctypes.sizeof(BMI); bi.biWidth = w; bi.biHeight = -h
    bi.biPlanes = 1; bi.biBitCount = 32; bi.biCompression = 0
    buf = ctypes.create_string_buffer(w * h * 4)
    gdi32.GetDIBits(mem, bmp, 0, h, buf, ctypes.byref(bi), 0)
    img = Image.frombuffer("RGBA", (w, h), buf, "raw", "BGRA", 0, 1).convert("RGB")
    out.parent.mkdir(parents=True, exist_ok=True)
    img.save(out)

    gdi32.DeleteObject(bmp); gdi32.DeleteDC(mem); user32.ReleaseDC(hwnd, hdc)
    return w, h


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("script")
    ap.add_argument("output")
    ap.add_argument("--cols", type=int, default=120)
    ap.add_argument("--rows", type=int, default=0,
                    help="0 = size to the output, so there is no dead space")
    ap.add_argument("--font-size", type=int, default=8)
    ap.add_argument("--env", action="append", default=[], metavar="KEY=VAL",
                    help="environment set for the run but NOT traced into the frame. "
                         "For boilerplate only (region, output format) -- bash traces "
                         "`export A=b` twice, which reads as a mistake. Anything that "
                         "changes what a command MEANS belongs in the script.")
    ap.add_argument("--title", default=None,
                    help="window title shown in the title bar of the figure")
    ap.add_argument("--redact", action="append", default=[],
                    help="extra literal that must not appear; repeatable")
    ap.add_argument("--allow-nonzero", action="store_true",
                    help="permit a non-zero exit from the commands")
    args = ap.parse_args()

    script = Path(args.script).resolve()
    out = Path(args.output).resolve()
    if not script.exists():
        raise SystemExit(f"no such script: {script}")

    # ---- 1. dry run, and scan the real text before any window opens ----
    print("running the commands once, headless, to scan the output...")
    extra_env = dict(e.split('=', 1) for e in args.env)
    rc, text = run_headless(script, extra_env)
    if rc != 0 and not args.allow_nonzero:
        print(text[-2000:])
        raise SystemExit(f"REFUSING TO CAPTURE: commands exited {rc}. "
                         "A figure of a failed run should be deliberate -- "
                         "pass --allow-nonzero if it is.")

    hits = scan(text, args.redact)
    if hits:
        print("\nREFUSING TO CAPTURE. The output contains:")
        for h in sorted(set(hits)):
            print(f"  - {h}")
        print("\nChange the COMMANDS so the value never appears -- project only the\n"
              "fields the figure needs with --query. Redacting the picture afterwards\n"
              "only removes what I thought to look for.")
        return 1
    print("  output is clean of account IDs, keys and personal paths")

    # ---- 2. run it again in a real terminal, and photograph that ----
    # Size the window to the output. A fixed 30 rows left half the figure as
    # dead black space, which reads as "something failed" rather than "done".
    rows = args.rows
    if not rows:
        wrapped = 0
        for line in text.splitlines():
            wrapped += max(1, -(-len(line) // args.cols))
        rows = min(60, max(8, wrapped + 2))

    title = args.title or f"lab-capture-{os.getpid()}"
    done = Path(tempfile.gettempdir()) / f"{title}.done"
    if done.exists():
        done.unlink()

    # Run the script as its OWN `bash -x`, from its own directory.
    #
    # Three defects this avoids, all visible in the first attempt:
    #   - `source` inside `-c` puts xtrace at depth 2, so bash prints "$$"
    #     instead of "$" (PS4's first character repeats with nesting).
    #   - sourcing by absolute path makes the first traced line the full
    #     C:/Projects/... path of this machine. Noise, and it leaks the local
    #     layout into a published figure.
    #   - the trailing `set +x` was itself traced and appeared in the frame.
    inner = (f'cd "{script.parent.as_posix()}" && '
             f'"{GIT_BASH}" --noprofile --norc -x "./{script.name}"; '
             f'touch "{done.as_posix()}"; sleep 600')
    cmd = [MINTTY, "-t", title, "-s", f"{args.cols},{rows}",
           "-o", f"Font=Consolas", "-o", f"FontHeight={args.font_size}",
           "-o", "ThemeFile=", "-o", "ForegroundColour=220,220,220",
           "-o", "BackgroundColour=26,32,44", "-o", "CursorColour=220,220,220",
           "-o", "Scrollbar=none", "-o", "ConfirmExit=no",
           "-h", "always",
           GIT_BASH, "--noprofile", "--norc", "-c", inner]
    env = dict(os.environ, PS4="$ ", **extra_env)
    proc = subprocess.Popen(cmd, env=env)

    print(f"opened a real terminal ({args.cols}x{rows}); waiting for the commands...")
    deadline = time.time() + 180
    while time.time() < deadline and not done.exists():
        time.sleep(0.4)
    if not done.exists():
        proc.kill()
        raise SystemExit("the commands did not finish in the terminal")
    time.sleep(1.2)   # let the last line paint

    hwnd = find_window(title)
    if not hwnd:
        proc.kill()
        raise SystemExit("could not find the terminal window to photograph")

    w, h = capture_window(hwnd, out)
    proc.kill()
    try:
        done.unlink()
    except OSError:
        pass

    print(f"Saved: {out}  ({w}x{h})")
    print("Every command line in that image was printed by bash from the command "
          "it ran. Nothing was retyped.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
