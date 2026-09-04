"""
A minimal MCP client that can talk to a Lambda Function URL.

WHY THIS EXISTS RATHER THAN AN OFF-THE-SHELF CLIENT
The server is behind AWS_IAM auth, so every request must be SigV4-signed. Most
MCP clients speak plain Streamable HTTP and have no idea how to sign an AWS
request, so they get a 403 from Lambda before any MCP code runs. This client
signs with the caller's existing credentials, which is the whole point of the
auth choice: no Cognito, no OAuth provider, no idle cost -- the identity is the
one already on the machine.

    python scripts/mcp_client.py <function-url> list
    python scripts/mcp_client.py <function-url> call get_daily_cost '{"days": 7}'
    python scripts/mcp_client.py <function-url> ask "what did I leave running"

`ask` is a deliberately dumb keyword router, not a model. It exists so the
end-to-end path can be demonstrated without an LLM in the loop -- proving the
transport and the tools work, separately from proving an agent can choose
between them.
"""
import json
import sys

import boto3
import requests
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest

SERVICE = "lambda"


def call(url, payload, region=None):
    session = boto3.Session()
    region = region or session.region_name or "us-east-1"
    creds = session.get_credentials()
    if creds is None:
        sys.exit("no AWS credentials found -- run scripts/ensure_aws_login.py first")

    body = json.dumps(payload)
    req = AWSRequest(method="POST", url=url, data=body,
                     headers={"Content-Type": "application/json"})
    SigV4Auth(creds.get_frozen_credentials(), SERVICE, region).add_auth(req)

    resp = requests.post(url, data=body, headers=dict(req.headers), timeout=45)
    if resp.status_code == 403:
        sys.exit("403 from Lambda: this identity is not allowed to invoke the "
                 "function URL, or the request was not signed correctly.")
    if resp.status_code == 202 or not resp.text:
        return None  # A notification. No response body is correct here.
    resp.raise_for_status()
    return resp.json()


def rpc(url, method, params=None, req_id=1):
    msg = {"jsonrpc": "2.0", "id": req_id, "method": method}
    if params is not None:
        msg["params"] = params
    return call(url, msg)


def unwrap(result):
    """Pull the text payload out of a tools/call result."""
    if not result or "result" not in result:
        return result
    content = result["result"].get("content") or []
    for block in content:
        if block.get("type") == "text":
            try:
                return json.loads(block["text"])
            except json.JSONDecodeError:
                return block["text"]
    return result["result"]


# A keyword router, not an agent. Each phrase maps to the tool a model would
# pick for that question.
ROUTES = [
    (("cost", "costing", "spend", "charge", "bill"), "get_daily_cost", {"days": 7}),
    (("untagged", "owner", "unowned", "orphan", "left"), "find_untagged_resources", {}),
    (("alarm", "monitoring", "alerting"), "get_alarm_state", {}),
    (("running", "deployed", "resources", "what is in"), "list_running_resources", {}),
]


def route(question):
    q = question.lower()
    for keywords, tool, args in ROUTES:
        if any(k in q for k in keywords):
            return tool, args
    return "list_running_resources", {}


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    url, command = sys.argv[1], sys.argv[2]

    init = rpc(url, "initialize", {"protocolVersion": "2025-06-18",
                                   "capabilities": {},
                                   "clientInfo": {"name": "week17-cli", "version": "1.0"}})
    server = init["result"]["serverInfo"]
    print("connected: %s %s (protocol %s)" % (
        server["name"], server["version"], init["result"]["protocolVersion"]))

    if command == "list":
        tools = rpc(url, "tools/list", req_id=2)["result"]["tools"]
        print("\n%d tools:" % len(tools))
        for t in tools:
            print("\n  %s" % t["name"])
            print("    %s" % t["description"])
        return

    if command == "call":
        name = sys.argv[3]
        args = json.loads(sys.argv[4]) if len(sys.argv) > 4 else {}
    elif command == "ask":
        question = " ".join(sys.argv[3:])
        name, args = route(question)
        print("\nquestion: %s" % question)
        print("routed to: %s%s" % (name, (" " + json.dumps(args)) if args else ""))
    else:
        sys.exit("unknown command: %s" % command)

    result = rpc(url, "tools/call", {"name": name, "arguments": args}, req_id=3)
    if result["result"].get("isError"):
        print("\nTOOL ERROR:")
    print()
    print(json.dumps(unwrap(result), indent=2)[:4000])


if __name__ == "__main__":
    main()
