"""
aws_console_url.py — turns the current AWS CLI/SSO session into a temporary
AWS Console login URL, using AWS's own documented federation endpoint.
No password is ever typed or stored; this only works because a real,
already-authenticated CLI session already exists (`aws sts get-caller-identity`
must succeed first).

Reference: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_enable-console-custom-url.html

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


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: python aws_console_url.py <destination_console_url>")
    print(get_signin_url(sys.argv[1]))
