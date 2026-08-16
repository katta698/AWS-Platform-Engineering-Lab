"""
Run an Athena query and render its real results as a PNG for the blog post.

Why render rather than screenshot the Athena console: the console shows a result
grid that is mostly chrome, truncates the interesting columns at typical widths,
and needs a click-to-run that produces a screenshot of a spinner as often as a
screenshot of data. This runs the query for real and lays the actual returned
rows out legibly. The data is genuine either way -- this only controls presentation.

Redaction here is deliberately paranoid, because this is a CUSTOM render and
capture.py's DOM redactor never sees it:

  * plain string replace, never a \\b\\d{12}\\b regex. Week 13 leaked an account
    ID that sat inside `<account-id>_MANAGED`, where `_` is a word character so
    the word boundary never matched.
  * an explicit assert before the file is written, so a miss fails loudly rather
    than producing a quietly-leaking image.

Usage:
    python render_query.py <sql-file> <output-png> "<Title>" [row-limit]
"""
import os
import subprocess
import sys
import time
from pathlib import Path

import boto3

REGION = os.environ.get("AWS_REGION", "us-east-1")
WORKGROUP = os.environ.get("ATHENA_WORKGROUP", "week14-flowlogs-wg")
DATABASE = os.environ.get("ATHENA_DATABASE", "week14_flowlogs_db")
TABLE = f'"{DATABASE}"."flow_logs"'

athena = boto3.client("athena", region_name=REGION)


def account_id() -> str:
    return subprocess.run(
        ["aws", "sts", "get-caller-identity", "--query", "Account", "--output", "text"],
        capture_output=True, text=True, timeout=30,
    ).stdout.strip()


def run(sql: str):
    qid = athena.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Database": DATABASE},
        WorkGroup=WORKGROUP,
    )["QueryExecutionId"]

    while True:
        ex = athena.get_query_execution(QueryExecutionId=qid)["QueryExecution"]
        state = ex["Status"]["State"]
        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        time.sleep(2)

    if state != "SUCCEEDED":
        raise SystemExit(f"query {state}: {ex['Status'].get('StateChangeReason')}")

    scanned = ex.get("Statistics", {}).get("DataScannedInBytes", 0)
    millis = ex.get("Statistics", {}).get("TotalExecutionTimeInMillis", 0)

    rows = []
    paginator = athena.get_paginator("get_query_results")
    for page in paginator.paginate(QueryExecutionId=qid):
        rows.extend(page["ResultSet"]["Rows"])

    header = [c.get("VarCharValue", "") for c in rows[0]["Data"]]
    body = [[c.get("VarCharValue", "") for c in r["Data"]] for r in rows[1:]]
    return header, body, scanned, millis


CSS = """
body { margin:0; padding:28px; background:#fff;
       font-family:'Segoe UI',-apple-system,Roboto,Helvetica,Arial,sans-serif; color:#212529; }
h2 { margin:0 0 4px 0; font-size:21px; color:#1a1a1a; }
.sub { color:#6c757d; font-size:13px; margin-bottom:16px; }
.sub b { color:#ED7100; }
table { border-collapse:collapse; font-size:13px; width:100%; }
th { background:#232F3E; color:#fff; text-align:left; padding:9px 12px;
     font-weight:600; white-space:nowrap; font-size:12px; letter-spacing:.02em; }
td { padding:8px 12px; border-bottom:1px solid #e9ecef; white-space:nowrap;
     font-family:'Cascadia Mono',Consolas,monospace; font-size:12.5px; }
tr:nth-child(even) td { background:#fafbfc; }
.num { text-align:right; }
.hl { color:#ED7100; font-weight:700; }
.foot { margin-top:14px; font-size:12px; color:#6c757d; }
"""


def is_num(v: str) -> bool:
    try:
        float(v)
        return True
    except (ValueError, TypeError):
        return False


def main():
    sql_file, out_png, title = sys.argv[1], sys.argv[2], sys.argv[3]
    limit = int(sys.argv[4]) if len(sys.argv) > 4 else 12

    sql = Path(sql_file).read_text(encoding="utf-8").replace("${table}", TABLE)
    header, body, scanned, millis = run(sql)
    body = body[:limit]

    acct = account_id()

    def clean(v: str) -> str:
        # Plain replace. See the module docstring for why this is not a regex.
        return (v or "").replace(acct, "<account-id>")

    header = [clean(h) for h in header]
    body = [[clean(c) for c in row] for row in body]

    rows_html = ""
    for row in body:
        cells = "".join(
            f'<td class="{"num" if is_num(c) else ""}">{c}</td>' for c in row
        )
        rows_html += f"<tr>{cells}</tr>"

    mib = scanned / 1048576.0
    cost = scanned / 1099511627776.0 * 5.0  # $5 per TB scanned

    html = f"""<!doctype html><html><head><meta charset="utf-8"><style>{CSS}</style></head><body>
<h2>{title}</h2>
<div class="sub">Athena workgroup <b>{WORKGROUP}</b> &middot; scanned
<b>{mib:.2f} MiB</b> in {millis/1000:.1f}s &middot; cost <b>${cost:.6f}</b>
at $5/TB &middot; {len(body)} of {len(body)} rows shown</div>
<table><thead><tr>{''.join(f'<th>{h}</th>' for h in header)}</tr></thead>
<tbody>{rows_html}</tbody></table>
<div class="foot">Real query output. Partition-filtered to the last 24h.</div>
</body></html>"""

    # Hard stop before anything is written to disk.
    assert acct not in html, "account ID survived redaction — refusing to render"

    tmp = Path(out_png).with_suffix(".html")
    tmp.write_text(html, encoding="utf-8")

    from playwright.sync_api import sync_playwright

    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": 1500, "height": 900})
        pg.goto(tmp.resolve().as_uri())
        pg.wait_for_timeout(600)
        # Screenshot the <body> element, not the page. full_page=True pads out to
        # the viewport height, so a short result table renders with several
        # hundred pixels of dead white space underneath -- which looks like a
        # broken image in a blog post. Clipping to the element crops to content.
        pg.locator("body").screenshot(path=out_png)
        b.close()

    tmp.unlink()
    print(f"Saved: {out_png}  ({len(body)} rows, {mib:.2f} MiB scanned)")


if __name__ == "__main__":
    main()
