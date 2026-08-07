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
import json
import os
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


def redact_strings(page, replacements: list) -> None:
    # Generic redactor for arbitrary secrets that capture.py can't resolve
    # itself (e.g. the subscriber email shown in an SNS subscriptions list).
    # Pass values via the REDACT_EXTRA env var (comma-separated) so nothing
    # sensitive is ever hardcoded into this committed script. Same
    # MutationObserver approach as the account-id redactor so late/re-rendered
    # nodes and value/title/aria-label attributes are all covered.
    if not replacements:
        return
    page.evaluate(
        """
        (pairs) => {
            const redactDoc = (doc) => {
                const body = doc.body || doc.documentElement;
                if (!body) return;
                pairs.forEach(([find, repl]) => {
                    if (!find) return;
                    const walker = doc.createTreeWalker(body, NodeFilter.SHOW_TEXT);
                    const hits = [];
                    let node;
                    while (node = walker.nextNode()) {
                        if (node.textContent.includes(find)) hits.push(node);
                    }
                    hits.forEach(n => n.textContent = n.textContent.split(find).join(repl));
                    body.querySelectorAll('[value],[title],[aria-label]').forEach(el => {
                        ['value', 'title', 'aria-label'].forEach(a => {
                            const v = el.getAttribute(a);
                            if (v && v.includes(find)) el.setAttribute(a, v.split(find).join(repl));
                        });
                        if (el.value && el.value.includes && el.value.includes(find)) {
                            el.value = el.value.split(find).join(repl);
                        }
                    });
                });
            };
            const runAll = () => {
                redactDoc(document);
                document.querySelectorAll('iframe').forEach(f => {
                    try {
                        const d = f.contentDocument;
                        if (d) {
                            redactDoc(d);
                            if (!f.__extraObs) {
                                f.__extraObs = true;
                                new MutationObserver(() => redactDoc(d)).observe(
                                    d.body || d.documentElement,
                                    {subtree: true, childList: true, characterData: true}
                                );
                            }
                        }
                    } catch (e) {}
                });
            };
            runAll();
            if (!window.__extraRedactorInstalled) {
                window.__extraRedactorInstalled = true;
                new MutationObserver(runAll).observe(
                    document.documentElement, {subtree: true, childList: true, characterData: true}
                );
            }
        }
        """,
        replacements,
    )


def redact_account_id(page, account_id: str) -> None:
    # AWS Console shows the account ID in the top-right account badge on
    # every page, AND in per-resource fields (e.g. EC2 SG "Owner"), ARNs,
    # and copy-button attributes. Blog posts are public - same rule as
    # READMEs never including the account ID. Found exposed on 3 real
    # screenshots, 2026-07-12 (03-ecs-cluster, 07-step-functions-execution,
    # 08-ecs-service-running) before this redaction existed; the "Owner"
    # field slipped through a one-shot text-walk on 2026-07-21 because it
    # loads async AFTER the redaction pass. Fix: run the replacement AND
    # install a MutationObserver so any late-rendered/re-rendered node is
    # caught too, plus cover common attributes (value/title/aria-label).
    # DOM replacement (not pixel-coordinate cropping) so this works
    # regardless of which console page or layout is being captured.
    page.evaluate(f"""
        () => {{
            const ACCT = '{account_id}';
            const redactDoc = (doc) => {{
                const body = doc.body || doc.documentElement;
                if (!body) return;
                const walker = doc.createTreeWalker(body, NodeFilter.SHOW_TEXT);
                const hits = [];
                let node;
                while (node = walker.nextNode()) {{
                    if (node.textContent.includes(ACCT)) hits.push(node);
                }}
                hits.forEach(n => n.textContent = n.textContent.split(ACCT).join('<account-id>'));
                body.querySelectorAll('[value],[title],[aria-label]').forEach(el => {{
                    ['value', 'title', 'aria-label'].forEach(a => {{
                        const v = el.getAttribute(a);
                        if (v && v.includes(ACCT)) el.setAttribute(a, v.split(ACCT).join('<account-id>'));
                    }});
                    if (el.value && el.value.includes && el.value.includes(ACCT)) {{
                        el.value = el.value.split(ACCT).join('<account-id>');
                    }}
                }});
            }};
            // AWS console renders many resource-detail panels inside same-origin
            // iframes; the top-document-only walk missed the EC2 SG "Owner"
            // field (2026-07-21). Descend into every reachable iframe too.
            const runAll = () => {{
                redactDoc(document);
                document.querySelectorAll('iframe').forEach(f => {{
                    try {{
                        const d = f.contentDocument;
                        if (d) {{
                            redactDoc(d);
                            if (!f.__acctObs) {{
                                f.__acctObs = true;
                                new MutationObserver(() => redactDoc(d)).observe(
                                    d.body || d.documentElement,
                                    {{subtree: true, childList: true, characterData: true}}
                                );
                            }}
                        }}
                    }} catch (e) {{}}
                }});
            }};
            runAll();
            if (!window.__acctRedactorInstalled) {{
                window.__acctRedactorInstalled = true;
                new MutationObserver(runAll).observe(
                    document.documentElement, {{subtree: true, childList: true, characterData: true}}
                );
            }}
        }}
    """)


def capture(url: str, output_path: Path, wait_selector: str | None, wait_ms: int | None,
            headed: bool, login_wait_seconds: int, height: int,
            click_text: str | None = None, click_wait_ms: int = 5000):
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

        # Resolve the account id up front (for AWS pages) and install the
        # redactor EARLY - its MutationObserver then runs through the whole
        # wait window, catching async-loaded fields (e.g. the EC2 SG "Owner")
        # that render after the initial pass.
        is_aws = "console.aws.amazon.com" in url or "signin.aws.amazon.com" in url
        account_id = get_aws_account_id() if is_aws else None
        # Fail LOUD, don't save, if we can't resolve the account id on an AWS
        # console page — a transient CLI hiccup returning None used to skip
        # redaction with only a WARNING and silently leak the account id into a
        # committed screenshot (caught on 05-eventbridge 2026-07-21). Refusing
        # to save is the safe default; re-run once creds are healthy.
        if is_aws and not account_id:
            context.close()
            raise SystemExit(
                "ERROR: could not resolve AWS account ID on an AWS console page — "
                "refusing to capture (would leak the account ID). Check AWS creds/SSO and retry."
            )
        # Extra secrets to redact (e.g. subscriber email) supplied out-of-band
        # via REDACT_EXTRA=comma,separated so nothing sensitive is committed.
        extras = [
            [s.strip(), "<redacted>"]
            for s in os.environ.get("REDACT_EXTRA", "").split(",")
            if s.strip()
        ]
        if account_id:
            redact_account_id(page, account_id)
        if extras:
            redact_strings(page, extras)

        if headed:
            print(f"Browser window open on this machine - log in within {login_wait_seconds}s...")
            page.wait_for_timeout(login_wait_seconds * 1000)

        if wait_selector:
            page.wait_for_selector(wait_selector, timeout=15000)
        if wait_ms:
            page.wait_for_timeout(wait_ms)

        # Some consoles render their tabs as client-side routes with no
        # addressable URL (AWS WAF's web ACL detail tabs use hash routing and
        # rewrite in place), so the only way to reach a tab is to click it.
        # Added 2026-08-05 for Week 13 after guessing tab slugs silently landed
        # on the default tab and produced convincingly-wrong screenshots.
        if click_text:
            # Try the tab role FIRST, then a link, then raw text. Plain text
            # matching is last because console side-nav items frequently reuse
            # a tab's label (CloudFront has both a "Security" nav section and a
            # "Security" tab) - matching the nav item collapses the sidebar and
            # leaves you on the default tab, producing a convincingly-wrong
            # screenshot with no error at all. Learned the hard way, Week 13.
            clicked = False
            for locator in (
                page.get_by_role("tab", name=click_text, exact=True),
                page.get_by_role("link", name=click_text, exact=True),
                page.get_by_text(click_text, exact=True),
            ):
                try:
                    locator.first.click(timeout=5000)
                    clicked = True
                    break
                except Exception:
                    continue
            if not clicked:
                context.close()
                raise SystemExit(
                    f"ERROR: could not click '{click_text}' — refusing to save a "
                    "screenshot of the wrong tab. Check the exact visible label."
                )
            page.wait_for_timeout(click_wait_ms)

        if account_id:
            redact_account_id(page, account_id)  # final pass; observer covers the rest
            print("Redacted account ID from page text before capture")
        if extras:
            redact_strings(page, extras)  # final pass
            print(f"Redacted {len(extras)} extra string(s) from REDACT_EXTRA")

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
    parser.add_argument("--click-text", default=None, help="Exact visible text to click before capturing (for SPA tabs with no addressable URL). Fails loudly rather than capturing the wrong tab.")
    parser.add_argument("--click-wait-ms", type=int, default=5000, help="Wait after the click before capturing")
    args = parser.parse_args()

    capture(args.url, args.output_path, args.wait_selector, args.wait_ms, args.headed, args.login_wait_seconds,
            args.height, args.click_text, args.click_wait_ms)
