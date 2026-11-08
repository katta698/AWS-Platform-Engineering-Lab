#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Does the isolation hold? Ten calls that answer it.

    python scripts/prove_isolation.py
    python scripts/prove_isolation.py --json results.json

Each case states what it EXPECTS before it runs, and the script exits non-zero
if any case disagrees. That matters more here than in most labs: three of
these cases expect to be allowed something they should not be allowed, and a
script that merely printed what happened would read the same whether the
finding reproduced or quietly stopped reproducing.

The three cases marked FINDING are the week. They are not bugs in this code
and not bugs in AWS; all three are documented behaviour that reads as safe:

  dax-crosses-tenant   AWS: "users inherit the permissions of the DAX
                       cluster's IAM policy ... No other permissions are
                       recognized."
  vacuous-scan         AWS: "A ForAllValues condition evaluates to true when
                       the condition key is not present in the request."
  attributes-on-request
                       AWS: "If no ProjectionExpression is provided in the
                       request, all attributes will be returned regardless of
                       any attribute restrictions in the policy."
"""
from __future__ import annotations

import argparse
import io
import json
import subprocess
import sys

import boto3

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

ALLOW = "allowed"
DENY = "denied"

# (id, function, event, expected, note)
CASES = [
    ("own-item-direct", "alpha",
     dict(op="get", path="direct", tenant_id="tenant-alpha", item_id="order-1"),
     ALLOW, "A tenant reads its own item. The baseline."),

    ("own-query-direct", "alpha",
     dict(op="query", path="direct", tenant_id="tenant-alpha"),
     ALLOW, "Query inside its own partition."),

    ("cross-tenant-direct", "alpha",
     dict(op="get", path="direct", tenant_id="tenant-beta", item_id="order-1"),
     DENY, "alpha asks for beta's item. LeadingKeys refuses it."),

    ("cross-query-direct", "alpha",
     dict(op="query", path="direct", tenant_id="tenant-beta"),
     DENY, "Same refusal for Query."),

    ("cross-tenant-dax", "alpha",
     dict(op="get", path="dax", tenant_id="tenant-beta", item_id="order-1"),
     ALLOW, "FINDING: the identical call, through the cache, succeeds."),

    ("cross-query-dax", "alpha",
     dict(op="query", path="dax", tenant_id="tenant-beta"),
     ALLOW, "FINDING: and so does the Query."),

    ("scan-guarded", "alpha",
     dict(op="scan", path="direct"),
     DENY, "The guarded policy does not grant Scan at all."),

    ("vacuous-scan", "audit",
     dict(op="scan", path="direct"),
     ALLOW, "FINDING: same condition without the Null guard. Scan carries no "
            "partition key, so the condition passes and every tenant returns."),

    ("no-projection-guarded", "alpha",
     dict(op="get", path="direct", tenant_id="tenant-alpha",
          item_id="order-1", project=False),
     DENY, "Select pinned to SPECIFIC_ATTRIBUTES, so a bare read is refused."),

    ("attributes-on-request", "audit",
     dict(op="get", path="direct", tenant_id="tenant-alpha",
          item_id="order-1", project=False),
     ALLOW, "FINDING: without that pin, omitting the projection returns "
            "secret_note, which the policy never allowed."),
]


def tf_output(name):
    out = subprocess.run(
        ["terraform", "output", "-json", name],
        cwd="terraform/environments/dev", capture_output=True, text=True)
    if out.returncode:
        sys.exit("terraform output %s failed:\n%s" % (name, out.stderr.strip()))
    return json.loads(out.stdout)


def invoke(lam, function_name, event):
    r = lam.invoke(FunctionName=function_name,
                   Payload=json.dumps(event).encode())
    payload = json.loads(r["Payload"].read() or b"{}")
    if "FunctionError" in r:
        return {"allowed": False, "error": "FunctionError",
                "message": json.dumps(payload)[:300]}
    return payload


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json", dest="json_path")
    a = ap.parse_args()

    functions = tf_output("functions")
    lam = boto3.client("lambda")

    rows, failures = [], 0
    for case_id, who, event, expected, note in CASES:
        got = invoke(lam, functions[who], event)
        actual = ALLOW if got.get("allowed") else DENY
        ok = actual == expected
        failures += not ok

        rows.append({
            "case": case_id, "principal": who, "event": event,
            "expected": expected, "actual": actual, "ok": ok, "note": note,
            "error": got.get("error"),
            "count": got.get("count"),
            "tenants_returned": got.get("tenants_returned"),
            "leaked_attributes": got.get("leaked_attributes"),
        })

    width = max(len(r["case"]) for r in rows)
    print("\n%-*s  %-6s  %-8s  %-8s  %s"
          % (width, "case", "who", "expected", "actual", "evidence"))
    print("-" * (width + 46))
    for r in rows:
        bits = []
        if r["error"]:
            bits.append(r["error"])
        if r["tenants_returned"]:
            bits.append("tenants=%s" % ",".join(r["tenants_returned"]))
        elif r["count"] is not None:
            bits.append("items=%d" % r["count"])
        if r["leaked_attributes"]:
            bits.append("LEAKED=%s" % ",".join(r["leaked_attributes"]))
        print("%s %-*s  %-6s  %-8s  %-8s  %s"
              % (" " if r["ok"] else "!", width, r["case"], r["principal"],
                 r["expected"], r["actual"], "; ".join(bits)))

    print()
    for r in rows:
        if r["note"].startswith("FINDING") and r["ok"]:
            print("  * %s" % r["note"])

    if failures:
        print("\n%d case(s) did not match what was expected. The lab has not "
              "shown what it claims to show -- read the table above before "
              "writing anything down." % failures)
    else:
        print("\n%d/%d cases behaved as expected." % (len(rows), len(rows)))

    if a.json_path:
        io.open(a.json_path, "w", encoding="utf-8").write(
            json.dumps(rows, indent=2))
        print("wrote %s" % a.json_path)

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
