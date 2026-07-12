"""
import_cookies.py — one-time import of an already-authenticated browser
session into the shared Playwright profile (playwright_profile/), so
capture.py can render HCP/ServiceNow pages headlessly without ever
attempting an automated sign-in (which gets blocked by OAuth bot-detection
— see SESSION_CONTEXT.md).

No login happens here at all. Jay logs into HCP/ServiceNow completely
normally, in his own regular browser, then exports the resulting session
cookies with a cookie-export extension (e.g. "Cookie-Editor" for
Chrome/Edge/Firefox — export as JSON). This script just loads those
already-valid cookies into the shared profile so future headless captures
are already authenticated, the same way restoring a browser session works.

Usage:
    python import_cookies.py <cookies.json>

Where <cookies.json> is a Cookie-Editor-style export: a JSON array of
objects with domain/name/value/path/expirationDate/httpOnly/secure/sameSite.

The cookies file itself is never committed and should be deleted after
import if you don't want the raw session tokens sitting on disk longer
than necessary - this script only needs it once.
"""
import json
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

REPO_ROOT = Path(__file__).resolve().parents[2]
PROFILE_DIR = REPO_ROOT / "playwright_profile"

SAME_SITE_MAP = {"lax": "Lax", "strict": "Strict", "no_restriction": "None", "unspecified": "Lax"}


def convert_cookie(raw: dict) -> dict:
    cookie = {
        "name": raw["name"],
        "value": raw["value"],
        "domain": raw["domain"],
        "path": raw.get("path", "/"),
        "httpOnly": raw.get("httpOnly", False),
        "secure": raw.get("secure", True),
        "sameSite": SAME_SITE_MAP.get(str(raw.get("sameSite", "lax")).lower(), "Lax"),
    }
    if raw.get("session") or "expirationDate" not in raw:
        cookie["expires"] = -1
    else:
        cookie["expires"] = int(raw["expirationDate"])
    return cookie


def main(cookies_path: str):
    raw_cookies = json.loads(Path(cookies_path).read_text())
    cookies = [convert_cookie(c) for c in raw_cookies]

    domains = sorted(set(c["domain"] for c in cookies))
    print(f"Importing {len(cookies)} cookies for domain(s): {', '.join(domains)}")

    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(str(PROFILE_DIR), headless=True)
        context.add_cookies(cookies)
        context.close()

    print("Done. Future headless capture.py runs against these domains will now be authenticated.")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python import_cookies.py <cookies.json>")
    main(sys.argv[1])
