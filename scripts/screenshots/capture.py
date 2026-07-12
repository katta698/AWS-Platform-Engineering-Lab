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
import subprocess
from pathlib import Path

from playwright.sync_api import sync_playwright

REPO_ROOT = Path(__file__).resolve().parents[2]  # .../AWS-Platform-Engineering-Lab
PROFILE_DIR = REPO_ROOT / "playwright_profile"


def get_aws_account_id() -> str | None:
    try:
        result = subprocess.run(
            ["aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text"],
            capture_output=True, text=True, timeout=10,
        )
        account_id = result.stdout.strip()
        return account_id if account_id else None
    except Exception:
        return None


def redact_account_id(page, account_id: str) -> None:
    # AWS Console shows the account ID in the top-right account badge on
    # every page. Blog posts are public - same rule as READMEs never
    # including the account ID. Found exposed on 3 real screenshots,
    # 2026-07-12 (03-ecs-cluster, 07-step-functions-execution,
    # 08-ecs-service-running) before this redaction existed.
    # DOM text replacement (not pixel-coordinate cropping) so this works
    # regardless of which console page or layout is being captured.
    page.evaluate(f"""
        () => {{
            const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
            let node;
            while (node = walker.nextNode()) {{
                if (node.textContent.includes('{account_id}')) {{
                    node.textContent = node.textContent.replaceAll('{account_id}', '<account-id>');
                }}
            }}
        }}
    """)


def capture(url: str, output_path: Path, wait_selector: str | None, wait_ms: int | None,
            headed: bool, login_wait_seconds: int, height: int):
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    with sync_playwright() as p:
        # Persistent context = cookies/localStorage survive between runs,
        # stored locally in PROFILE_DIR (gitignored - never commit this).
        # Viewport height is configurable per capture (--height), not
        # full_page=True: full_page grabs the whole scrollable DOM, which on
        # SPA pages often includes a long tail of empty space below a
        # stuck-loading widget (confirmed on a real AWS Console capture,
        # 2026-07-12). But a fixed short viewport can equally crop out real,
        # relevant content further down a genuinely content-full page
        # (confirmed on a real HCP run-list capture, same day - lost 2 of 4
        # real runs at height=900). Pick --height per page based on what's
        # actually needed, not a single default that fits neither case well.
        context = p.chromium.launch_persistent_context(
            str(PROFILE_DIR),
            headless=not headed,
            viewport={"width": 1400, "height": height},
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

        if "console.aws.amazon.com" in url or "signin.aws.amazon.com" in url:
            account_id = get_aws_account_id()
            if account_id:
                redact_account_id(page, account_id)
                print(f"Redacted account ID from page text before capture")
            else:
                print("WARNING: could not resolve AWS account ID to redact - check manually before publishing")

        # full_page=False (viewport-only, 1400x900) is the deliberate choice
        # here, not full_page=True - SPA pages (AWS Console especially) often
        # reserve DOM height for widgets that never finish loading (e.g. a
        # stuck "Loading" Container Insights chart), producing a long tail of
        # pure empty space in a full-page capture. Confirmed on a real
        # screenshot 2026-07-12: ~500px of blank space below the actual
        # footer. Viewport-only crops that out automatically.
        page.screenshot(path=str(output_path), full_page=False)
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
    parser.add_argument("--height", type=int, default=900, help="Viewport height in px - increase for pages with real content below the fold")
    args = parser.parse_args()

    capture(args.url, args.output_path, args.wait_selector, args.wait_ms, args.headed, args.login_wait_seconds, args.height)
