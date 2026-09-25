"""
aws_console_url.py — turns the current AWS CLI/SSO session into a temporary
AWS Console login URL, using AWS's own documented federation endpoint.
No password is ever typed or stored; this only works because a real,
already-authenticated CLI session already exists (`aws sts get-caller-identity`
must succeed first).

Reference: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_enable-console-custom-url.html

WHY YOU ARE READING THIS INSTEAD OF SIGNING IN (added 2026-09-24)
-----------------------------------------------------------------
This file has existed since 11 July 2026. On 24 September I asked Jay to sign
in to the AWS console by hand -- twice -- while this script sat in the same
directory, and then started writing a second copy of it. His answer:

    "Why do you keep making same and same same mistakes all the time? We were
     the one who discussed there has to be a sign in without expiry and we did
     that. And every time you ask the same question, can you sign in."

So: a lapsed console session is NEVER a reason to ask a human for anything. As
long as `aws sts get-caller-identity` succeeds, a console session can be minted
from it. capture.py now calls open_console_session() automatically when it hits
a sign-in page, refreshes, and retries once -- so the question does not get
asked at all.

THE LOGIN URL IS A CREDENTIAL. Anyone holding it is signed in as this role.
open_console_session() hands it straight to the local browser; it is never
printed, logged, or pasted into chat. Printing it from __main__ is for a human
who explicitly asked for it.


Usage:
    python aws_console_url.py "https://console.aws.amazon.com/ecs/v2/clusters/fargate-selfservice-cluster-dev/services"

Prints a one-time-use console URL (valid ~15 min, or until the underlying
CLI session expires, whichever is sooner) that logs straight into the
console at the given destination page.
"""
import json
import subprocess
import sys
import urllib.parse

import requests


def get_signin_url(destination: str) -> str:
    creds_raw = subprocess.check_output(
        ["aws", "configure", "export-credentials", "--format", "process"]
    )
    creds = json.loads(creds_raw)

    session = {
        "sessionId": creds["AccessKeyId"],
        "sessionKey": creds["SecretAccessKey"],
        "sessionToken": creds["SessionToken"],
    }

    federation_url = (
        "https://signin.aws.amazon.com/federation"
        f"?Action=getSigninToken&Session={urllib.parse.quote(json.dumps(session))}"
    )
    resp = requests.get(federation_url)
    resp.raise_for_status()
    signin_token = resp.json()["SigninToken"]

    login_url = (
        "https://signin.aws.amazon.com/federation"
        f"?Action=login&Issuer=AWSPlatformEngineeringLab"
        f"&Destination={urllib.parse.quote(destination)}"
        f"&SigninToken={signin_token}"
    )
    return login_url


def open_console_session(destination: str, cdp_port: int) -> None:
    """Sign the debug Chrome on `cdp_port` into the console at `destination`.

    Opens the tab over plain HTTP (/json/new) rather than the DevTools
    websocket: Chrome 111+ rejects those when they carry an Origin header, which
    is the same bug that makes Playwright's connect_over_cdp hang.
    """
    import urllib.request
    url = get_signin_url(destination)
    endpoint = "http://127.0.0.1:%d/json/new?%s" % (
        cdp_port, urllib.parse.quote(url, safe=""))
    req = urllib.request.Request(endpoint, method="PUT")
    with urllib.request.urlopen(req, timeout=30):
        pass


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python aws_console_url.py <destination_console_url>")
    print(get_signin_url(sys.argv[1]))
