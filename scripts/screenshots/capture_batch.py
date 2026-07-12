"""
capture_batch.py — for services where the real session depends on true
browser-session-only cookies (no expiration — confirmed on ServiceNow's
glide_user_activity/glide_node_id_for_js, 2026-07-12), which get dropped the
moment a browser context closes. import_cookies.py + a separate capture.py
run doesn't work for these, because the session-only cookies never survive
between the two separate process runs.

This script loads the cookies AND takes every screenshot in one continuous
browser session that never closes in between, so session-only cookies stay
valid for the whole batch.

Usage:
    python capture_batch.py <cookies.json> <url1>=<output1> [<url2>=<output2> ...]

Example:
    python capture_batch.py snow_cookies.json \
      "https://dev388443.service-now.com/nav_to.do?uri=...=05-servicenow-catalog-item.png" \
      "https://dev388443.service-now.com/nav_to.do?uri=...=06-servicenow-ticket-submitted.png"
"""
import json
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

REPO_ROOT = Path(__file__).resolve().parents[2]
PROFILE_DIR = REPO_ROOT / "playwright_profile_batch"  # separate from the persistent one - this is throwaway per run

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


def main(cookies_path: str, pairs: list[str]):
    raw_cookies = json.loads(Path(cookies_path).read_text())
    cookies = [convert_cookie(c) for c in raw_cookies]

    with sync_playwright() as p:
        context = p.chromium.launch_persistent_context(str(PROFILE_DIR), headless=True, viewport={"width": 1400, "height": 900})
        context.add_cookies(cookies)
        page = context.new_page()

        for pair in pairs:
            url, output_path = pair.rsplit("=", 1)
            output_path = Path(output_path)
            output_path.parent.mkdir(parents=True, exist_ok=True)
            page.goto(url, wait_until="load", timeout=30000)
            page.wait_for_timeout(6000)
            page.screenshot(path=str(output_path), full_page=True)
            print(f"Saved: {output_path}")

        context.close()


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("Usage: python capture_batch.py <cookies.json> <url1>=<output1> [<url2>=<output2> ...]")
    main(sys.argv[1], sys.argv[2:])
