"""
Check whether the AWS SSO session is usable, and if it is not, start a login
that can be approved from a phone.

Why this exists (2026-08-29): Jay drives these sessions remotely from his phone
and has no terminal. The default `aws sso login` uses the authorization-code
flow, which redirects to http://127.0.0.1:<port>/oauth/callback -- a phone
browser cannot route to the Windows machine's localhost, so approval dies with
"site can't be reached". The device-code flow has no localhost hop: you open a
URL, type a short code, and the CLI polls and writes the token itself.

Several turns were burned diagnosing that as a truncated URL and then as a
network fault. It was neither. This script removes the diagnosis entirely.

Also worth knowing: IAM Identity Center session-duration changes apply only to
NEW sessions, and the maximum is 90 days. There is no never-expiring option, so
this will recur.

Usage:
    python scripts/ensure_aws_login.py                 # check, log in if needed, wait
    python scripts/ensure_aws_login.py --check-only    # report only, never log in
    python scripts/ensure_aws_login.py --profile workload-sso
    python scripts/ensure_aws_login.py --timeout 300

Exit codes:
    0  session is valid (already, or after a successful approval)
    1  session is invalid and was not repaired (--check-only, timeout, or error)
"""
import argparse
import datetime as dt
import json
import pathlib
import re
import subprocess
import sys
import threading

DEFAULT_PROFILE = "personal"
SSO_CACHE = pathlib.Path.home() / ".aws" / "sso" / "cache"

# The device-code flow prints the verification URL, then the code, then an
# autofill URL carrying the code as a query parameter. The autofill one is what
# we want to hand over -- it is a single tap.
AUTOFILL_RE = re.compile(r"https://\S+/start/#/device\?user_code=(\S+)")
PLAIN_URL_RE = re.compile(r"https://\S+/start/#/device\b")
CODE_RE = re.compile(r"^\s*([A-Z0-9]{4}-[A-Z0-9]{4})\s*$")


def run(args, timeout=60):
    return subprocess.run(
        args, capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace"
    )


def caller_identity(profile):
    """Return the identity dict, or None if the session is not usable."""
    p = run(["aws", "sts", "get-caller-identity", "--profile", profile, "--output", "json"])
    if p.returncode != 0:
        return None
    try:
        return json.loads(p.stdout)
    except json.JSONDecodeError:
        return None


def cached_token_expiry(profile):
    """Best-effort expiry of the cached access token for this profile's start URL.

    Purely informational -- get-caller-identity is the authority, because a
    token can be revoked well before its stated expiry.
    """
    start_url = None
    cfg = pathlib.Path.home() / ".aws" / "config"
    if cfg.exists():
        text = cfg.read_text(encoding="utf-8", errors="replace")
        m = re.search(rf"^\[profile {re.escape(profile)}\]\n(.*?)(?=^\[|\Z)", text, re.S | re.M)
        session = re.search(r"^sso_session\s*=\s*(\S+)", m.group(1), re.M) if m else None
        if session:
            s = re.search(
                rf"^\[sso-session {re.escape(session.group(1))}\]\n(.*?)(?=^\[|\Z)",
                text,
                re.S | re.M,
            )
            if s:
                u = re.search(r"^sso_start_url\s*=\s*(\S+)", s.group(1), re.M)
                start_url = u.group(1) if u else None

    if not start_url or not SSO_CACHE.is_dir():
        return None

    newest = None
    for f in SSO_CACHE.glob("*.json"):
        try:
            d = json.loads(f.read_text(encoding="utf-8", errors="replace"))
        except (json.JSONDecodeError, OSError):
            continue
        # Only access tokens matter; the long-dated entries are client
        # registrations and grant nothing on their own.
        if not d.get("accessToken") or d.get("startUrl") != start_url:
            continue
        exp = d.get("expiresAt")
        if exp and (newest is None or exp > newest):
            newest = exp
    return newest


def report_valid(profile, ident):
    print(f"SSO session VALID for profile '{profile}'")
    print(f"  account : {ident.get('Account')}")
    print(f"  arn     : {ident.get('Arn')}")
    exp = cached_token_expiry(profile)
    if exp:
        print(f"  expires : {exp}")
        try:
            when = dt.datetime.fromisoformat(exp.replace("Z", "+00:00"))
            left = when - dt.datetime.now(dt.timezone.utc)
            hours = left.total_seconds() / 3600
            if hours < 24:
                print(f"  NOTE    : only {hours:.1f}h left -- may expire mid-session")
        except ValueError:
            pass


def login(profile, timeout):
    """Start a device-code login, print the URL and code, wait for approval."""
    proc = subprocess.Popen(
        ["aws", "sso", "login", "--profile", profile, "--use-device-code", "--no-browser"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )

    url = code = None
    printed = False
    lines = []

    def pump():
        nonlocal url, code, printed
        for line in proc.stdout:
            lines.append(line)
            m = AUTOFILL_RE.search(line)
            if m:
                url, code = m.group(0), m.group(1)
            elif not url:
                m = PLAIN_URL_RE.search(line)
                if m:
                    url = m.group(0)
            m = CODE_RE.match(line)
            if m and not code:
                code = m.group(1)
            if url and code and not printed:
                printed = True
                print()
                print("=" * 68)
                print("APPROVE THIS LOGIN -- works from a phone, no localhost involved")
                print("=" * 68)
                print(f"  code : {code}")
                print(f"  open : {url}")
                print("=" * 68)
                print("Waiting for approval... the token is written here automatically.")
                print(flush=True)

    t = threading.Thread(target=pump, daemon=True)
    t.start()

    try:
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        print(f"\nTimed out after {timeout}s waiting for approval.", file=sys.stderr)
        print("The code has likely expired -- run this again for a fresh one.", file=sys.stderr)
        return False

    t.join(timeout=5)

    if proc.returncode != 0:
        print("\nLogin failed:", file=sys.stderr)
        print("".join(lines[-15:]), file=sys.stderr)
        return False
    if not printed:
        # No URL ever appeared: usually a malformed profile or an aws CLI too
        # old for --use-device-code. Show what it actually said.
        print("\nLogin produced no verification URL:", file=sys.stderr)
        print("".join(lines[-15:]), file=sys.stderr)
        return False
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", default=DEFAULT_PROFILE)
    ap.add_argument(
        "--check-only",
        action="store_true",
        help="report session state and exit; never start a login",
    )
    ap.add_argument(
        "--timeout",
        type=int,
        default=600,
        help="seconds to wait for approval (default 600)",
    )
    args = ap.parse_args()

    ident = caller_identity(args.profile)
    if ident:
        report_valid(args.profile, ident)
        return 0

    exp = cached_token_expiry(args.profile)
    print(f"SSO session INVALID for profile '{args.profile}'"
          + (f" (cached token expired {exp})" if exp else ""))

    if args.check_only:
        return 1

    if not login(args.profile, args.timeout):
        return 1

    ident = caller_identity(args.profile)
    if not ident:
        print("Login reported success but the session is still unusable.", file=sys.stderr)
        return 1

    print("\nApproved.")
    report_valid(args.profile, ident)
    return 0


if __name__ == "__main__":
    sys.exit(main())
