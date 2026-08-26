"""
capture_servicenow.py — screenshots of ServiceNow record pages.

ServiceNow needs its own entry point because two of its behaviours defeat the
generic capture.py:

  1. RECORD PAGES ONLY EXIST INSIDE THE UI SHELL. A direct link such as
     /oauth_entity.do?sys_id=... redirects to the login screen even with a valid
     session, so there is no addressable URL for "this record". The only way in
     is to open the list and click the row.

  2. THE CONTENT IS IN AN IFRAME. Everything lives in `gsft_main`, so a
     page-level click never finds the link -- capture.py's --click-text fails
     with "could not click", which is accurate and unhelpful.

Redaction, the leak assertion and the login-page guard are imported from
capture.py rather than reimplemented: those checks exist because they each
caught a real leak, and a second copy would drift.

Usage:
    python capture_servicenow.py <list-url> <row-text> <output.png> [--height N]

Example:
    python capture_servicenow.py \
      "https://devXXXXXX.service-now.com/nav_to.do?uri=oauth_entity_list.do" \
      "AWS DevOps Agent" \
      week-16-.../docs/blog/screenshots/06-snow-oauth-entity.png
"""
import argparse
import os
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parent))
from capture import (  # noqa: E402  -- shared on purpose, see module docstring
    assert_not_a_login_page,
    assert_not_present,
    get_aws_account_id,
    get_org_account_ids,
    redact_account_id,
    redact_strings,
    settle,
)

CDP_PORT = 9222


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("list_url", help="A ServiceNow LIST url (nav_to.do?uri=..._list.do)")
    ap.add_argument("row_text", help="Exact visible text of the row to open. Empty string captures the list itself.")
    ap.add_argument("output_path")
    ap.add_argument("--height", type=int, default=1000)
    ap.add_argument("--wait-ms", type=int, default=9000)
    ap.add_argument("--cdp", type=int, default=CDP_PORT)
    args = ap.parse_args()

    out = Path(args.output_path)
    out.parent.mkdir(parents=True, exist_ok=True)

    account_id = get_aws_account_id()
    org_accounts = get_org_account_ids(account_id)
    extras = [[a, "<member-account-id>"] for a in org_accounts]
    extras += [[s.strip(), "<redacted>"] for s in os.environ.get("REDACT_EXTRA", "").split(",") if s.strip()]

    with sync_playwright() as p:
        browser = p.chromium.connect_over_cdp(f"http://127.0.0.1:{args.cdp}")
        context = browser.contexts[0] if browser.contexts else browser.new_context()
        page = context.new_page()
        try:
            page.set_viewport_size({"width": 1400, "height": args.height})
            page.goto(args.list_url, wait_until="domcontentloaded", timeout=45000)
            settle(page, "servicenow list")
            page.wait_for_timeout(args.wait_ms)

            if args.row_text:
                # The row link is inside gsft_main. Search every frame rather
                # than assuming the frame name, since ServiceNow renames it
                # between the classic UI and workspace views.
                clicked = False
                for frame in page.frames:
                    try:
                        link = frame.get_by_text(args.row_text, exact=True).first
                        if link.count() > 0:
                            link.click(timeout=8000)
                            clicked = True
                            break
                    except Exception:
                        continue
                if not clicked:
                    raise SystemExit(
                        f"Could not find a row reading {args.row_text!r} in any frame.\n"
                        "Check the exact visible text, or pass an empty string to capture the list."
                    )
                settle(page, "servicenow record")
                page.wait_for_timeout(args.wait_ms)

            if account_id:
                redact_account_id(page, account_id)
            if extras:
                redact_strings(page, extras)
            page.wait_for_timeout(400)

            if account_id:
                assert_not_present(page, account_id, "the AWS account ID")
            for needle, _ in extras:
                assert_not_present(page, needle, f"the REDACT_EXTRA value '{needle[:6]}...'")
            assert_not_a_login_page(page, False)

            page.screenshot(path=str(out), full_page=False)
            print(f"Saved: {out}")
        finally:
            try:
                page.close()   # never leak a page -- a jammed target list kills the CDP session
            except Exception:
                pass


if __name__ == "__main__":
    main()
