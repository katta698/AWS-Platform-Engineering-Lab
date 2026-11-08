"""One tenant API, two paths to the same table.

The code is identical for every tenant. What differs is the execution role
attached to the function, and -- the point of the week -- which path the
request takes to reach the data:

    path="direct"   boto3 -> DynamoDB endpoint
                    The role's dynamodb:LeadingKeys condition is evaluated.

    path="dax"      amazondax -> DAX cluster -> DynamoDB
                    The role's dynamodb: conditions are NOT evaluated. AWS:
                    "users inherit the permissions of the DAX cluster's IAM
                    policy when they access that cluster ... No other
                    permissions are recognized."

Both paths are exercised against the same item so the difference is the path
and nothing else.

Event shape
-----------
    {
      "op":        "get" | "query" | "scan",
      "path":      "direct" | "dax",
      "tenant_id": "tenant-alpha",      # partition key to ask for
      "item_id":   "order-1",           # sort key, for op=get
      "project":   true                 # send a ProjectionExpression
    }

`project` exists because dynamodb:Attributes is evaluated on the REQUEST, not
the response: "If no ProjectionExpression is provided in the request, all
attributes will be returned regardless of any attribute restrictions in the
policy." Setting it false is how the lab shows that.

Errors are returned, not raised. An AccessDeniedException is the expected
result of half these calls and is evidence, not a failure.
"""
import json
import os

import boto3
from boto3.dynamodb.conditions import Key

TABLE = os.environ["TABLE_NAME"]
DAX_ENDPOINT = os.environ.get("DAX_ENDPOINT", "")
TENANT = os.environ["TENANT_ID"]

# Attributes this tenant's policy allows. `secret_note` is deliberately not
# in the list, so a projection that asks for it is refused and a request with
# no projection at all returns it anyway.
ALLOWED = ["tenant_id", "item_id", "description", "amount"]

_direct = None
_dax = None


def direct_table():
    global _direct
    if _direct is None:
        _direct = boto3.resource("dynamodb").Table(TABLE)
    return _direct


def dax_table():
    """Lazily built: importing amazondax costs ~200ms and the direct path
    never needs it."""
    global _dax
    if _dax is None:
        from amazondax import AmazonDaxClient
        _dax = AmazonDaxClient.resource(endpoint_url=DAX_ENDPOINT).Table(TABLE)
    return _dax


def table_for(path):
    if path == "dax":
        if not DAX_ENDPOINT:
            raise RuntimeError("DAX_ENDPOINT is not set on this function")
        return dax_table()
    return direct_table()


def run(table, op, tenant_id, item_id, project):
    kwargs = {}
    if project:
        # ProjectionExpression needs #placeholders: several of these names
        # are not reserved words today, but the policy lists them and a
        # reserved word appearing later would fail at runtime rather than here.
        kwargs["ProjectionExpression"] = ", ".join("#%s" % a for a in ALLOWED)
        kwargs["ExpressionAttributeNames"] = {"#%s" % a: a for a in ALLOWED}

    if op == "get":
        r = table.get_item(Key={"tenant_id": tenant_id, "item_id": item_id},
                           **kwargs)
        item = r.get("Item")
        return [item] if item else []

    if op == "query":
        r = table.query(KeyConditionExpression=Key("tenant_id").eq(tenant_id),
                        **kwargs)
        return r.get("Items", [])

    if op == "scan":
        # Carries no partition key, which is exactly why a ForAllValues
        # LeadingKeys condition does not constrain it.
        r = table.scan(**kwargs)
        return r.get("Items", [])

    raise ValueError("unknown op: %r" % op)


def handler(event, context):
    op = event.get("op", "get")
    path = event.get("path", "direct")
    tenant_id = event.get("tenant_id", TENANT)
    item_id = event.get("item_id", "order-1")
    project = event.get("project", True)

    result = {
        "function_tenant": TENANT,
        "asked_for_tenant": tenant_id,
        "op": op,
        "path": path,
        "projection_sent": bool(project),
    }

    try:
        items = run(table_for(path), op, tenant_id, item_id, project)
    except Exception as exc:                       # noqa: BLE001
        # An AccessDeniedException here is the isolation control working.
        name = type(exc).__name__
        code = getattr(exc, "response", {}).get("Error", {}).get("Code", name)
        result.update(allowed=False, error=code, message=str(exc)[:300])
        print(json.dumps(result))
        return result

    tenants = sorted({i.get("tenant_id") for i in items if i.get("tenant_id")})
    result.update(
        allowed=True,
        count=len(items),
        tenants_returned=tenants,
        # The giveaway for the attribute finding: an attribute the policy
        # never allowed, present in the response.
        leaked_attributes=sorted(
            {k for i in items for k in i if k not in ALLOWED}),
        items=json.loads(json.dumps(items, default=str)),
    )
    print(json.dumps({k: v for k, v in result.items() if k != "items"}))
    return result
