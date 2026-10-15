"""The service being protected.

It returns a rate. It does not check who called it, it cannot see the caller's
identity, and it has no authorisation code at all. That is deliberate and it is
the entire argument of the week: by the time a request reaches this function,
VPC Lattice has already decided the caller was allowed to make it.

Compare that with the usual arrangement, where every service re-implements
"is this caller allowed" in its own middleware, slightly differently, and the
answer lives in code nobody audits.
"""

import json


def handler(event, context):
    method = (event.get("method") or event.get("httpMethod") or "GET").upper()
    path = event.get("path") or "/"

    print("served %s %s" % (method, path))

    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({
            "service": "rates",
            "method": method,
            "path": path,
            "rate": 42.5,
            "note": "this function performed no authorisation of its own",
        }),
    }
