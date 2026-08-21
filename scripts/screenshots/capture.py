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
    # Timeout raised from 10s to 30s, with one retry, after a real silent leak on
    # Week 14 (2026-08-15): the call takes ~5s idle but ran past 10s while
    # Playwright was launching Chromium concurrently. It returned None, redaction
    # was skipped, and an HCP page with a role ARN saved with the account ID
    # visible. The call is cheap and runs once per capture -- there is no reason
    # for the timeout to be tight enough to lose a race with a browser launch.
    for attempt in (1, 2):
        try:
            result = subprocess.run(
                ["aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text"],
                capture_output=True, text=True, timeout=30,
            )
            account_id = result.stdout.strip()
            if account_id:
                return account_id
            if attempt == 1:
                print(f"WARNING: STS returned no account id (rc={result.returncode}), retrying...")
        except Exception as exc:
            if attempt == 1:
                print(f"WARNING: STS call failed ({type(exc).__name__}), retrying...")
    return None


def get_org_account_ids(caller_account_id: str | None) -> list[str]:
    """
    Every OTHER account ID in the organization.

    Added on Week 15, the first build with an organization trail. Until then the
    caller's own account ID was the only one that could appear on screen, so
    redacting that single value was sufficient. An org trail changes that: the S3
    console lists one folder PER MEMBER ACCOUNT under AWSLogs/<org-id>/, and
    Athena results carry an `account` column. Those are real account IDs of real
    accounts, and the standing rule against publishing an account ID does not
    only cover the one you happen to be logged into.

    Caught on a real capture (03-s3-org-prefix, 2026-08-20): the member account
    ID rendered in plain text while the caller's was correctly redacted.

    Returns an empty list, with a warning, when the account is not in an
    organization or lacks organizations:ListAccounts. That is not a silent
    fail-open: a standalone account has no sibling IDs to leak, and the caller's
    own ID is still redacted and asserted separately.
    """
    try:
        result = subprocess.run(
            ["aws", "organizations", "list-accounts", "--query", "Accounts[].Id", "--output", "text"],
            capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            print("NOTE: could not list organization accounts (not an org, or no permission);")
            print("      only the caller's own account ID will be redacted.")
            return []
        ids = [a for a in result.stdout.split() if a and a != caller_account_id]
        if ids:
            print(f"Found {len(ids)} other organization account ID(s) to redact")
        return ids
    except Exception as exc:
        print(f"NOTE: organization lookup failed ({type(exc).__name__}); caller account only.")
        return []


def assert_not_a_login_page(page, allow_login_page: bool) -> None:
    """
    Refuse to save a screenshot of a sign-in screen.

    The redaction assertions answer "did anything leak", not "did we capture the
    page we asked for". A login page passes every one of them trivially, because
    it contains no account ID and no secrets -- it just contains nothing useful.

    Caught the hard way on Week 15 (2026-08-20): an expired HCP session sent both
    `01-hcp-runs` and `01b-hcp-workspace-variables` to the same sign-in screen.
    Both saved cleanly, both were reported as captured, and both went into a blog
    post as two identical pictures of a login form.

    Deliberately narrow. It looks for a sign-in HEADING or a password field, not
    for the word "login" anywhere on the page -- an IAM console page legitimately
    says "sign-in" all over itself, and a check that cries wolf gets bypassed.
    """
    if allow_login_page:
        return

    hit = page.evaluate("""
        () => {
            const pw = document.querySelector('input[type="password"]');
            if (pw && pw.offsetParent !== null) return 'a visible password field';
            for (const el of document.querySelectorAll('h1,h2,[role="heading"]')) {
                const t = (el.textContent || '').trim().toLowerCase();
                if (/^(sign in|log in|login|sign in to |welcome back)/.test(t)) {
                    return 'a heading reading "' + (el.textContent || '').trim().slice(0, 60) + '"';
                }
            }
            return null;
        }
    """)

    if hit:
        raise SystemExit(
            "REFUSING TO SAVE: this looks like a sign-in page (%s).\n"
            "The session for this service has expired. Re-run with --headed and\n"
            "--login-wait-seconds to sign in by hand; the profile is persistent, so\n"
            "later captures reuse the session.\n"
            "If the sign-in screen IS the intended subject, pass --allow-login-page."
            % hit
        )


def assert_not_present(page, needle: str, label: str) -> None:
    """
    Positive check that a secret is genuinely absent from the rendered page.

    The redactors are best-effort DOM rewrites. This asserts the outcome instead
    of trusting that they ran -- it is the automated form of the standing rule
    that every console screenshot must be read back before being committed,
    which exists because blind redaction has under-covered a leak more than once.

    Descends into same-origin iframes for the same reason the redactor does:
    AWS renders resource-detail panels in them and a top-document check never
    sees that content.
    """
    found = page.evaluate(
        """
        (needle) => {
            const hit = (doc) => {
                try {
                    if (doc.body && doc.body.innerText && doc.body.innerText.includes(needle)) return true;
                } catch (e) { /* cross-origin */ }
                for (const f of Array.from(doc.querySelectorAll('iframe'))) {
                    try { if (f.contentDocument && hit(f.contentDocument)) return true; }
                    catch (e) { /* cross-origin */ }
                }
                return false;
            };
            return hit(document);
        }
        """,
        needle,
    )
    if found:
        raise SystemExit(
            f"ERROR: {label} is STILL VISIBLE in the rendered page after redaction — "
            "refusing to save. The redactor did not reach it (shadow DOM, canvas, "
            "or an image). Capture this one manually and redact with PIL, then "
            "read the image back to confirm."
        )


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
            click_text: str | None = None, click_wait_ms: int = 5000,
            allow_unresolved_account: bool = False):
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
        # Resolve the account id for EVERY page, not just AWS console pages.
        #
        # This used to be `if is_aws else None`, which scoped account-ID redaction
        # to AWS Console URLs only. That assumption is wrong: the account ID shows
        # up in plenty of non-AWS surfaces. Found live on Week 14 (2026-08-15) —
        # an HCP Terraform workspace variables page renders
        # TFC_AWS_RUN_ROLE_ARN as arn:aws:iam::<account>:role/... in plain text,
        # and the capture saved it unredacted because app.terraform.io is not an
        # AWS domain. The same exposure exists on any page that displays a role
        # ARN: HCP, ServiceNow, GitHub Actions logs, a CI dashboard.
        #
        # Resolving it always and redacting whenever it resolves costs one cached
        # STS call and removes the whole class of bug. The fail-loud below stays
        # scoped to AWS pages: a non-AWS capture should not be blocked just
        # because an SSO session happens to be expired.
        account_id = get_aws_account_id()
        org_account_ids = get_org_account_ids(account_id)
        # Fail LOUD, don't save, if we can't resolve the account id on an AWS
        # console page — a transient CLI hiccup returning None used to skip
        # redaction with only a WARNING and silently leak the account id into a
        # committed screenshot (caught on 05-eventbridge 2026-07-21). Refusing
        # to save is the safe default; re-run once creds are healthy.
        # Refuse on ANY page, not just AWS console pages.
        #
        # This guard used to be `if is_aws and not account_id`. That is what let
        # the Week 14 leak through: an HCP page is not an AWS domain, so an
        # unresolved account id skipped both the redaction and this check, and
        # the capture saved happily with the ARN in plain text. Any page can
        # display a role ARN, so "we could not resolve the thing we redact" is a
        # stop condition everywhere.
        #
        # The escape hatch is deliberate but explicit: --allow-unresolved-account
        # for capturing a genuinely AWS-free page while SSO happens to be dead.
        if not account_id and not allow_unresolved_account:
            context.close()
            raise SystemExit(
                "ERROR: could not resolve the AWS account ID — refusing to capture, "
                "because any page may render a role ARN and redaction cannot run "
                "without it.\n"
                "  Fix:  aws sso login    (then retry)\n"
                "  Or:   pass --allow-unresolved-account if this page provably "
                "contains no AWS identifiers."
            )
        # Extra secrets to redact (e.g. subscriber email) supplied out-of-band
        # via REDACT_EXTRA=comma,separated so nothing sensitive is committed.
        extras = [
            [s.strip(), "<redacted>"]
            for s in os.environ.get("REDACT_EXTRA", "").split(",")
            if s.strip()
        ]
        # Member account IDs go through the same path as REDACT_EXTRA so they
        # inherit its assert_not_present() check for free.
        extras = [[a, "<member-account-id>"] for a in org_account_ids] + extras
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

        # Verify the redaction actually worked rather than assuming it did.
        # Running the redactor and checking the result are different things --
        # this is the check that would have caught the Week 14 HCP leak at the
        # moment it happened instead of on a manual read-back afterwards.
        if account_id:
            assert_not_present(page, account_id, "the AWS account ID")
        for needle, _ in extras:
            assert_not_present(page, needle, f"the REDACT_EXTRA value '{needle[:4]}...'")
        print("Verified: no unredacted secrets in the rendered page")

        # Separate question from the leak checks above: is this the page we asked
        # for at all? A sign-in screen passes every redaction assertion.
        assert_not_a_login_page(page, args.allow_login_page)

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
    parser.add_argument("--allow-login-page", action="store_true",
                        help="Permit saving a page that looks like a sign-in screen "
                             "(only when the sign-in screen is genuinely the subject)")
    parser.add_argument("--allow-unresolved-account", action="store_true",
                        help="Capture even if the AWS account ID cannot be resolved. Only for pages that provably contain no AWS identifiers -- normally you want `aws sso login` instead.")
    args = parser.parse_args()

    capture(args.url, args.output_path, args.wait_selector, args.wait_ms, args.headed, args.login_wait_seconds,
            args.height, args.click_text, args.click_wait_ms, args.allow_unresolved_account)
