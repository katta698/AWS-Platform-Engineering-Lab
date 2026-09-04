"""
An MCP server that lets you ask an AWS account what it is doing.

WHY THIS EXISTS
On 2026-08-30 the question "what is running, what is it costing, and did we
leave anything behind" took eleven API calls across Cost Explorer, CloudTrail,
Resource Groups Tagging, CloudWatch and Terraform Cloud. The data was there the
whole time. What was missing was a way to ask.

Four tools, all read-only. The IAM role this runs under has no write action of
any kind, so a manipulated model cannot change the account -- it can only
report on it. That is deliberate: the top MCP risk in current guidance is tool
poisoning, where instructions hidden in a tool description or parameter schema
steer the model. A read-only server makes that a disclosure problem rather than
a destruction one.

TRANSPORT
Streamable HTTP over a Lambda Function URL with AWS_IAM auth, so the caller's
own SigV4-signed identity is the authorization. No API Gateway and no Cognito
means nothing bills while idle. The trade is that the client must sign
requests; an off-the-shelf client that cannot would need API Gateway + OAuth,
which is the production path described in the README.

THE COST TRAP THIS IS BUILT AROUND
ce:GetCostAndUsage bills $0.01 PER REQUEST and each page counts separately.
Nearly every other read here is free. An LLM decides when to call a tool and
will happily re-ask the same question several times in a conversation, so the
cost tool is cached in DynamoDB with a TTL. Without that, a chatty session
silently bills cents at a time -- which is the failure mode this whole week
exists to catch.
"""
import datetime as dt
import decimal
import json
import os
import time

import boto3
from botocore.config import Config

BOTO = Config(retries={"max_attempts": 3, "mode": "standard"})

CACHE_TABLE = os.environ.get("CACHE_TABLE", "")
CACHE_TTL_SECONDS = int(os.environ.get("CACHE_TTL_SECONDS", "3600"))
PROTOCOL_VERSION = "2025-06-18"
SERVER_NAME = "aws-platform-ops"
SERVER_VERSION = "1.0.0"

ce = boto3.client("ce", config=BOTO)
tagging = boto3.client("resourcegroupstaggingapi", config=BOTO)
cw = boto3.client("cloudwatch", config=BOTO)
ddb = boto3.resource("dynamodb") if CACHE_TABLE else None


# ---------------------------------------------------------------- cache ----
def cached(key, producer):
    """Return a cached answer if still fresh, otherwise produce and store it.

    Only the Cost Explorer tool uses this. The others call free APIs, where a
    cache would add staleness for no saving.
    """
    if not ddb:
        return producer()
    table = ddb.Table(CACHE_TABLE)
    try:
        item = table.get_item(Key={"cache_key": key}).get("Item")
        if item and int(item.get("expires_at", 0)) > int(time.time()):
            body = json.loads(item["payload"])
            body["_cached"] = True
            return body
    except Exception:
        # A cache failure must never fail the tool. Worst case we pay a cent.
        pass
    value = producer()
    try:
        table.put_item(Item={
            "cache_key": key,
            "payload": json.dumps(value, default=str),
            "expires_at": int(time.time()) + CACHE_TTL_SECONDS,
        })
    except Exception:
        pass
    return value


def _f(x):
    return float(decimal.Decimal(str(x)))


# ---------------------------------------------------------------- tools ----
def tool_daily_cost(days=7):
    """Cost by service per day. THE ONLY TOOL HERE THAT COSTS MONEY TO CALL."""
    days = max(1, min(int(days), 90))
    end = dt.date.today() + dt.timedelta(days=1)
    start = end - dt.timedelta(days=days + 1)
    key = "cost:%s:%s" % (start, end)

    def produce():
        r = ce.get_cost_and_usage(
            TimePeriod={"Start": start.isoformat(), "End": end.isoformat()},
            Granularity="DAILY", Metrics=["UnblendedCost"],
            GroupBy=[{"Type": "DIMENSION", "Key": "SERVICE"}])
        out, totals = [], {}
        for period in r["ResultsByTime"]:
            rows = []
            for g in period["Groups"]:
                amt = _f(g["Metrics"]["UnblendedCost"]["Amount"])
                if amt < 0.005:
                    continue
                svc = g["Keys"][0]
                rows.append({"service": svc, "usd": round(amt, 2)})
                totals[svc] = round(totals.get(svc, 0) + amt, 2)
            out.append({"date": period["TimePeriod"]["Start"],
                        "total_usd": round(sum(x["usd"] for x in rows), 2),
                        "services": sorted(rows, key=lambda x: -x["usd"])})
        return {"days": out,
                "by_service_total": dict(sorted(totals.items(), key=lambda kv: -kv[1])),
                "note": "Cost Explorer bills $0.01 per request; this answer is cached."}

    return cached(key, produce)


def tool_running_resources():
    """Every tagged resource in the account, grouped by service. Free to call."""
    services, sample = {}, {}
    for page in tagging.get_paginator("get_resources").paginate(ResourcesPerPage=100):
        for res in page["ResourceTagMappingList"]:
            arn = res["ResourceARN"]
            parts = arn.split(":")
            svc = parts[2] if len(parts) > 2 else "unknown"
            services[svc] = services.get(svc, 0) + 1
            sample.setdefault(svc, []).append(arn.split(":")[-1][:80])
    return {"total": sum(services.values()),
            "by_service": dict(sorted(services.items(), key=lambda kv: -kv[1])),
            "examples": {k: v[:3] for k, v in sample.items()}}


def tool_untagged_resources(required_tag="Project"):
    """Resources missing an ownership tag -- the ones nobody will claim.

    A resource with no owner tag is the one that survives a teardown, because
    nobody knows which project it belonged to. Two buckets from Week 12 did
    exactly that: a script created them outside Terraform, so destroy never
    knew they existed.
    """
    missing = []
    for page in tagging.get_paginator("get_resources").paginate(ResourcesPerPage=100):
        for res in page["ResourceTagMappingList"]:
            keys = {t["Key"] for t in res.get("Tags", [])}
            if required_tag not in keys:
                missing.append({"arn": res["ResourceARN"], "tags": sorted(keys)})
    return {"required_tag": required_tag, "count": len(missing),
            "resources": missing[:50], "truncated": len(missing) > 50}


def tool_alarm_state():
    """Every CloudWatch alarm and its state. Free to call.

    An alarm in INSUFFICIENT_DATA is not reassuring -- it means nothing has
    reported. Week 15 shipped an alarm that latched in ALARM and stopped
    notifying, which is worse than a false positive because the failure mode
    is silence rather than noise.
    """
    alarms = []
    for page in cw.get_paginator("describe_alarms").paginate():
        for a in page.get("MetricAlarms", []):
            alarms.append({"name": a["AlarmName"], "state": a["StateValue"],
                           "metric": a.get("MetricName"),
                           "period_seconds": a.get("Period"),
                           "actions_enabled": a.get("ActionsEnabled")})
    by_state = {}
    for a in alarms:
        by_state[a["state"]] = by_state.get(a["state"], 0) + 1
    return {"count": len(alarms), "by_state": by_state, "alarms": alarms[:50]}


TOOLS = [
    {"name": "get_daily_cost",
     "description": ("Cost per day, broken down by AWS service, for the last N days. "
                     "Use this to answer what an account is being charged for and whether "
                     "spend has changed. Cached for an hour because the underlying API "
                     "bills per request."),
     "inputSchema": {"type": "object",
                     "properties": {"days": {"type": "integer", "minimum": 1, "maximum": 90,
                                             "description": "How many days back to report"}},
                     "required": []},
     "fn": lambda a: tool_daily_cost(a.get("days", 7))},
    {"name": "list_running_resources",
     "description": ("Every tagged resource currently in the account, counted by service, "
                     "with example identifiers. Use this to answer what is actually "
                     "deployed right now."),
     "inputSchema": {"type": "object", "properties": {}, "required": []},
     "fn": lambda a: tool_running_resources()},
    {"name": "find_untagged_resources",
     "description": ("Resources missing an ownership tag. Use this to find things nobody "
                     "owns, which are the things that survive a teardown."),
     "inputSchema": {"type": "object",
                     "properties": {"required_tag": {"type": "string",
                                                     "description": "Tag key that marks ownership"}},
                     "required": []},
     "fn": lambda a: tool_untagged_resources(a.get("required_tag", "Project"))},
    {"name": "get_alarm_state",
     "description": ("Every CloudWatch alarm with its current state, period and whether "
                     "actions are enabled. Use this to answer whether monitoring is "
                     "actually working."),
     "inputSchema": {"type": "object", "properties": {}, "required": []},
     "fn": lambda a: tool_alarm_state()},
]
TOOL_INDEX = {t["name"]: t for t in TOOLS}


# ------------------------------------------------------------ protocol ----
def rpc_result(req_id, result):
    return {"jsonrpc": "2.0", "id": req_id, "result": result}


def rpc_error(req_id, code, message):
    return {"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}}


def dispatch(message):
    """Handle one JSON-RPC message. Returns None for notifications.

    MCP notifications (method starting 'notifications/') carry no id and MUST
    NOT get a response -- returning one to a notification is a protocol error
    that some clients treat as fatal.
    """
    method = message.get("method")
    req_id = message.get("id")

    if method == "initialize":
        return rpc_result(req_id, {
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {"tools": {"listChanged": False}},
            "serverInfo": {"name": SERVER_NAME, "version": SERVER_VERSION}})

    if method and method.startswith("notifications/"):
        return None

    if method == "ping":
        return rpc_result(req_id, {})

    if method == "tools/list":
        return rpc_result(req_id, {"tools": [
            {k: t[k] for k in ("name", "description", "inputSchema")} for t in TOOLS]})

    if method == "tools/call":
        params = message.get("params") or {}
        name = params.get("name")
        tool = TOOL_INDEX.get(name)
        if not tool:
            return rpc_error(req_id, -32602, "unknown tool: %s" % name)
        try:
            payload = tool["fn"](params.get("arguments") or {})
            text = json.dumps(payload, indent=2, default=str)
            return rpc_result(req_id, {"content": [{"type": "text", "text": text}],
                                       "isError": False})
        except Exception as exc:
            # Report the failure through the protocol rather than as a 500, so
            # the model can say what broke instead of silently finding nothing.
            return rpc_result(req_id, {
                "content": [{"type": "text",
                             "text": "%s failed: %s: %s" % (name, type(exc).__name__, exc)}],
                "isError": True})

    return rpc_error(req_id, -32601, "method not found: %s" % method)


def lambda_handler(event, context):
    raw = event.get("body") or "{}"
    if event.get("isBase64Encoded"):
        import base64
        raw = base64.b64decode(raw).decode("utf-8")

    try:
        message = json.loads(raw)
    except json.JSONDecodeError:
        return {"statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps(rpc_error(None, -32700, "parse error"))}

    if isinstance(message, list):
        responses = [r for r in (dispatch(m) for m in message) if r is not None]
        body = json.dumps(responses) if responses else ""
    else:
        response = dispatch(message)
        body = json.dumps(response) if response is not None else ""

    # A notification produces no body: 202 with an empty payload is what the
    # Streamable HTTP transport expects, not 200 with "null".
    if not body:
        return {"statusCode": 202, "headers": {"Content-Type": "application/json"}, "body": ""}

    return {"statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": body}
