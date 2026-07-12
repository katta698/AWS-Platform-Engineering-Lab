"""
capture.py — shared screenshot automation for every week's blog post.

Uses a PERSISTENT browser profile (playwright_profile/, gitignored, repo
root) so login sessions for AWS Console / HCP Terraform / ServiceNow survive
across runs and across weeks — log in once per service, not once per
screenshot.

Usage:
    python capture.py <url> <output_path> [--wait-selector CSS] [--wait-ms N] [--headed] [--login-wait-seconds N]

Examples:
    # Public URL, no login needed
    python capture.py "http://alb-dns/demo-nginx/" week-09-.../docs/blog/screenshots/10-live-service-url.png

    # First-time login to an authenticated service: opens a REAL browser
    # window on this machine and waits a fixed window (default 90s) for you
    # to log in by hand, then captures and saves the session automatically.
    # No terminal keypress needed - this does NOT block on input(), since a
    # script invoked by Claude has no way to react to you finishing a login
    # in real time. Just log in before the timer runs out.
    python capture.py "https://app.terraform.io/app/katta/workspaces/week-09-dev" out.png --headed --login-wait-seconds 90

    # Subsequent runs reuse the saved session automatically (headless is fine)
    python capture.py "https://app.terraform.io/app/katta/workspaces/week-09-dev/runs" out.png
"""
import argparse
from pathlib import Path

from playwright.sync_api import sync_playwright

REPO_ROOT = Path(__file__).resolve().parents[2]  # .../AWS-Platform-Engineering-Lab
PROFILE_DIR = REPO_ROOT / "playwright_profile"


def capture(url: str, output_path: Path, wait_selector: str | None, wait_ms: int | None,
            headed: bool, login_wait_seconds: int):
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        # Persistent context = cookies/localStorage survive between runs,
        # stored locally in PROFILE_DIR (gitignored - never commit this).
        context = p.chromium.launch_persistent_context(
            str(PROFILE_DIR),
            headless=not headed,
            viewport={"width": 1400, "height": 900},
        )
        page = context.new_page()
        # "networkidle" doesn't work for SPA-heavy pages (AWS Console, HCP UI)
        # that poll continuously in the background and never go idle -
        # confirmed via a real 30s timeout testing against the ECS console.
        # "load" + an explicit wait is the reliable choice for these.
        page.goto(url, wait_until="load", timeout=30000)

        if headed:
            print(f"Browser window open on this machine - log in within {login_wait_seconds}s...")
            page.wait_for_timeout(login_wait_seconds * 1000)

        if wait_selector:
            page.wait_for_selector(wait_selector, timeout=15000)
        if wait_ms:
            page.wait_for_timeout(wait_ms)

        page.screenshot(path=str(output_path), full_page=True)
        context.close()

    print(f"Saved: {output_path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("url")
    parser.add_argument("output_path")
    parser.add_argument("--wait-selector", default=None, help="CSS selector to wait for before capturing")
    parser.add_argument("--wait-ms", type=int, default=1000, help="Extra wait time in ms before capturing")
    parser.add_argument("--headed", action="store_true", help="Show the browser window (needed for first-time login)")
    parser.add_argument("--login-wait-seconds", type=int, default=90, help="Fixed wait window for manual login in --headed mode")
    args = parser.parse_args()

    capture(args.url, args.output_path, args.wait_selector, args.wait_ms, args.headed, args.login_wait_seconds)
