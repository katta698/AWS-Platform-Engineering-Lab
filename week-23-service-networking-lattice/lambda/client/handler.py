"""The caller.

One function, three behaviours, chosen by the event:

    {"mode": "signed"}                       sign as this function's own role
    {"mode": "signed", "role_arn": "..."}    sign as a DIFFERENT role
    {"mode": "unsigned"}                     send nothing at all

That is the whole experiment. The network position never changes -- same VPC,
same subnet, same security group, same function. Only the identity changes. If
Lattice is doing what it claims, the first succeeds and the other two do not.

Signing detail worth knowing: the SigV4 service name is "vpc-lattice-svcs",
not "vpc-lattice". The second is the control plane (creating service networks);
the first is the data plane (calling through one). Sign with the wrong name and
you get a 403 that looks exactly like a policy denial.
"""

import json
import os
import urllib.request

import boto3
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest

SIGV4_SERVICE = "vpc-lattice-svcs"

SERVICE_URL = os.environ.get("SERVICE_URL", "")
REGION = os.environ.get("AWS_REGION", "us-east-1")


def credentials_for(role_arn):
    """Session credentials to sign with. This function's own role if None."""
    if not role_arn:
        return boto3.Session().get_credentials()
    sts = boto3.client("sts")
    assumed = sts.assume_role(RoleArn=role_arn, RoleSessionName="wk23-caller")["Credentials"]
    return boto3.Session(
        aws_access_key_id=assumed["AccessKeyId"],
        aws_secret_access_key=assumed["SecretAccessKey"],
        aws_session_token=assumed["SessionToken"],
    ).get_credentials()


def build_request(url, method, body, creds):
    """Returns (headers, data). Signs only when creds is not None.

    Pure enough to reason about: given the same inputs it builds the same
    request, and the unsigned path provably carries no Authorization header.
    """
    data = body.encode() if body else None
    req = AWSRequest(method=method, url=url, data=data)
    if creds is not None:
        SigV4Auth(creds, SIGV4_SERVICE, REGION).add_auth(req)
    headers = dict(req.headers)
    if data and "content-type" not in {k.lower() for k in headers}:
        headers["content-type"] = "application/json"
    return headers, data


def handler(event, context):
    mode = (event.get("mode") or "signed").lower()
    method = (event.get("method") or "GET").upper()
    path = event.get("path") or "/"
    body = event.get("body")
    url = (event.get("url") or SERVICE_URL).rstrip("/") + path

    creds = None
    if mode == "signed":
        creds = credentials_for(event.get("role_arn"))

    headers, data = build_request(url, method, body, creds)
    signed = "authorization" in {k.lower() for k in headers}
    print("calling %s %s mode=%s signed=%s role=%s"
          % (method, url, mode, signed, event.get("role_arn") or "(own)"))

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            payload = resp.read().decode("utf-8", "replace")
            out = {"status": resp.status, "signed": signed, "body": payload[:400]}
    except urllib.error.HTTPError as exc:
        # A denial is a result, not a failure. 403 here is the policy working.
        out = {"status": exc.code, "signed": signed,
               "body": exc.read().decode("utf-8", "replace")[:400]}
    except Exception as exc:                                    # noqa: BLE001
        out = {"status": None, "signed": signed, "error": "%s: %s" % (type(exc).__name__, exc)}

    print("result=%s" % json.dumps(out))
    return out


def self_test():
    """python handler.py --self-test"""
    import datetime

    class FakeCreds:
        access_key = "AKIAEXAMPLE"
        secret_key = "secret"
        token = None

        def get_frozen_credentials(self):
            return self

    url = "https://rates-123.vpc-lattice-svcs.us-east-1.on.aws/rates"
    cases = []

    h_unsigned, d_unsigned = build_request(url, "GET", None, None)
    cases.append(("an unsigned request carries no Authorization header",
                  "authorization" not in {k.lower() for k in h_unsigned}))
    cases.append(("an unsigned GET has no body", d_unsigned is None))

    h_signed, _ = build_request(url, "GET", None, FakeCreds())
    low = {k.lower() for k in h_signed}
    cases.append(("a signed request carries an Authorization header", "authorization" in low))
    cases.append(("it signs for vpc-lattice-svcs, not vpc-lattice",
                  SIGV4_SERVICE in h_signed.get("Authorization", "")
                  and "/vpc-lattice/" not in h_signed.get("Authorization", "")))

    h_post, d_post = build_request(url, "POST", '{"a":1}', FakeCreds())
    cases.append(("a POST body is encoded", d_post == b'{"a":1}'))
    cases.append(("a POST sets a content type",
                  "content-type" in {k.lower() for k in h_post}))

    bad = 0
    for label, ok in cases:
        print("  [%s] %s" % ("PASS" if ok else "DEAD", label))
        bad += not ok
    print()
    if bad:
        print("%d case(s) DO NOT WORK." % bad)
        return 1
    print("All %d caller cases pass." % len(cases))
    return 0


if __name__ == "__main__":
    import sys
    sys.exit(self_test() if "--self-test" in sys.argv else 0)
