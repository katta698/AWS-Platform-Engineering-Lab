"""
A stdio-to-SigV4 bridge, so a real MCP client can reach the server.

THE PROBLEM THIS SOLVES
The server sits behind a Lambda Function URL with AWS_IAM auth, which means
every request must carry an AWS SigV4 signature. That choice is why the
endpoint costs nothing while idle and needs no Cognito user pool -- the
caller's existing AWS identity is the authorization.

It is also why Claude Desktop, Cursor and every other off-the-shelf MCP client
gets a 403. They speak plain Streamable HTTP and have no idea how to sign an
AWS request.

This bridge sits between them. The client launches it as an ordinary stdio MCP
server; it reads JSON-RPC on stdin, signs each message, forwards it over HTTPS,
and writes the response to stdout. The client never knows AWS was involved, and
the server never sees an unsigned request.

    claude mcp add aws-platform-ops -- python <path to this file> <function-url>

WHY A BRIDGE RATHER THAN CHANGING THE SERVER
Swapping the Function URL for API Gateway plus an OAuth provider would remove
the need for this entirely, and is the right answer for a team. For one
operator it adds two always-present services to avoid one 60-line script.
"""
import json
import sys

import boto3
import requests
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest

SERVICE = "lambda"


def log(msg):
    # stdout is the protocol channel and must carry nothing but JSON-RPC.
    # Anything diagnostic goes to stderr or it corrupts the stream.
    print("[bridge] %s" % msg, file=sys.stderr, flush=True)


def main():
    if len(sys.argv) < 2:
        sys.exit("usage: mcp_stdio_bridge.py <function-url>")
    url = sys.argv[1]

    session = boto3.Session()
    region = session.region_name or "us-east-1"
    creds = session.get_credentials()
    if creds is None:
        sys.exit("no AWS credentials -- run scripts/ensure_aws_login.py first")
    log("signing for %s as region %s" % (url, region))

    http = requests.Session()

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue

        body = line
        req = AWSRequest(method="POST", url=url, data=body,
                         headers={"Content-Type": "application/json"})
        SigV4Auth(creds.get_frozen_credentials(), SERVICE, region).add_auth(req)

        try:
            resp = http.post(url, data=body, headers=dict(req.headers), timeout=60)
        except Exception as exc:
            log("transport error: %s" % exc)
            continue

        # A notification gets 202 and an empty body. Forwarding anything here
        # would put a response on the wire for a message that must not have
        # one, which some clients treat as fatal.
        if resp.status_code == 202 or not resp.text.strip():
            continue

        if resp.status_code >= 400:
            log("HTTP %s from server: %s" % (resp.status_code, resp.text[:200]))
            try:
                req_id = json.loads(body).get("id")
            except json.JSONDecodeError:
                req_id = None
            if req_id is not None:
                sys.stdout.write(json.dumps({
                    "jsonrpc": "2.0", "id": req_id,
                    "error": {"code": -32000,
                              "message": "upstream returned HTTP %s" % resp.status_code}}) + "\n")
                sys.stdout.flush()
            continue

        sys.stdout.write(resp.text.strip() + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()
