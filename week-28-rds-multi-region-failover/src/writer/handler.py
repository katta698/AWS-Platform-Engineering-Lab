# -*- coding: utf-8 -*-
"""Write rows to the primary so replication has something to fall behind on.

    {"rows": 20000}

Returns the row count and the primary's own commit timestamp, which the
failover measurement compares against what the replica holds.
"""
import json
import os
import time

import psycopg2

DDL = """
CREATE TABLE IF NOT EXISTS orders (
    id         bigserial PRIMARY KEY,
    written_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    payload    text NOT NULL
)
"""


def connect():
    return psycopg2.connect(
        host=os.environ["DB_HOST"],
        dbname=os.environ["DB_NAME"],
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASS"],
        connect_timeout=10,
        # The instance is encrypted at rest; in transit is a separate setting
        # and RDS Postgres accepts TLS by default. Require it explicitly so a
        # misconfiguration fails rather than silently downgrading.
        sslmode="require",
    )


def handler(event, context):
    rows = int(event.get("rows", 20_000))
    t0 = time.time()

    conn = connect()
    conn.autocommit = False
    with conn.cursor() as cur:
        cur.execute(DDL)
        conn.commit()

        # executemany would round-trip per row. One multi-row INSERT per
        # batch keeps the write rate high enough to produce measurable lag.
        batch = 500
        payload = "x" * 512
        for start in range(0, rows, batch):
            n = min(batch, rows - start)
            cur.execute(
                "INSERT INTO orders (payload) VALUES " +
                ",".join(["(%s)"] * n), [payload] * n)
            conn.commit()

        cur.execute("SELECT count(*), max(written_at) FROM orders")
        count, last = cur.fetchone()
    conn.close()

    return {
        "rows_written": rows,
        "rows_in_table": count,
        "last_write": last.isoformat(),
        "seconds": round(time.time() - t0, 1),
    }
