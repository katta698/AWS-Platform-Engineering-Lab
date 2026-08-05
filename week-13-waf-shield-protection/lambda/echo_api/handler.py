"""
Echo origin behind the WAF.

This function exists to be a target. Its only job is to prove whether a
request survived the firewall: if you see this JSON, WAF let the request
through. If you see a 403 with a WAF body instead, a rule matched and the
request never reached here.

It deliberately reflects back the parts of the request the WAF inspects
(path, query string, a safe subset of headers) so the attack simulation
can show *what* was sent alongside *whether it got through*. Header values
are truncated and the sensitive ones are dropped -- an echo endpoint that
mirrors an Authorization header back into CloudWatch logs is its own
vulnerability.
"""

import json
import os

# Never echo these back, even though the WAF inspects some of them. An echo
# endpoint is a classic accidental credential-disclosure primitive.
SENSITIVE_HEADERS = {
    "authorization",
    "cookie",
    "x-api-key",
    "x-amz-security-token",
    "proxy-authorization",
}

MAX_VALUE_LEN = 200


def _safe_headers(headers):
    """Drop sensitive headers, truncate the rest."""
    safe = {}
    for key, value in (headers or {}).items():
        if key.lower() in SENSITIVE_HEADERS:
            safe[key] = "<redacted>"
            continue
        text = str(value)
        if len(text) > MAX_VALUE_LEN:
            text = text[:MAX_VALUE_LEN] + "...<truncated>"
        safe[key] = text
    return safe


def handler(event, context):
    request_context = event.get("requestContext", {})
    identity = request_context.get("identity", {})

    body = {
        "message": "Request reached the origin. WAF allowed it.",
        "stage": os.environ.get("STAGE", "unknown"),
        "path": event.get("path"),
        "httpMethod": event.get("httpMethod"),
        "queryStringParameters": event.get("queryStringParameters"),
        "sourceIp": identity.get("sourceIp"),
        # Present only when the request came via CloudFront, so the
        # attack simulation can tell the edge path from the direct-to-origin
        # path without guessing.
        "viaCloudFront": "cloudfront-viewer-address" in {
            k.lower() for k in (event.get("headers") or {})
        },
        "headers": _safe_headers(event.get("headers")),
        "requestId": request_context.get("requestId"),
    }

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            # This endpoint is a demo target, not a browser app. No CORS
            # allowance is granted deliberately.
            "Cache-Control": "no-store",
        },
        "body": json.dumps(body, indent=2),
    }
