#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Put a few items in each tenant's partition.

    python scripts/seed.py

Written with the deployer's own credentials, not a tenant role. The tenant
roles are read-only by design -- a tenant that can write its neighbour's
partition is a different lab.

Every item carries a `secret_note`. It is not in the policies' allowed
attribute list, so it is the thing that should never come back. When it does,
that is the attribute finding showing itself rather than a wrong guess about
what a policy says.
"""
from __future__ import annotations

import json
import subprocess
import sys

import boto3

TENANTS = {
    "tenant-alpha": [
        ("order-1", "Laptop refresh, 40 units", 61200),
        ("order-2", "Annual support renewal", 18750),
        ("order-3", "Datacentre rack decommission", 9400),
    ],
    "tenant-beta": [
        ("order-1", "Warehouse scanners, 120 units", 33600),
        ("order-2", "Cold storage retrofit", 128000),
    ],
}


def tf_output(name):
    out = subprocess.run(
        ["terraform", "output", "-json", name],
        cwd="terraform/environments/dev",
        capture_output=True, text=True,
    )
    if out.returncode:
        sys.exit("terraform output %s failed:\n%s" % (name, out.stderr.strip()))
    return json.loads(out.stdout)


def main() -> int:
    table_name = tf_output("table_name")
    table = boto3.resource("dynamodb").Table(table_name)

    written = 0
    for tenant, rows in TENANTS.items():
        for item_id, description, amount in rows:
            table.put_item(Item={
                "tenant_id": tenant,
                "item_id": item_id,
                "description": description,
                "amount": amount,
                # Not in allowed_attributes. Should be unreachable.
                "secret_note": "%s internal margin note -- not for other tenants"
                               % tenant,
            })
            written += 1
        print("  %-14s %d item(s)" % (tenant, len(rows)))

    print("\n%d item(s) written to %s" % (written, table_name))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
