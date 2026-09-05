"""
EBS Savings API — Phase 1 Lambda handler (CUR only)

Data flow:  CUR Parquet (S3) → Glue catalog → Athena → this Lambda → API Gateway → Dashboard

Phase 1 scope:
  - Overview, By Account, By Region, By Volume Type tabs  ✓
  - Volume Inventory tab                                   ✗  (returns empty list)
  - No cross-account EC2 calls — zero IAM role assumptions
  - No AWS Organizations API calls
"""
import json
import os
import time
import boto3

ATHENA_DATABASE  = os.environ["ATHENA_DATABASE"]
ATHENA_WORKGROUP = os.environ["ATHENA_WORKGROUP"]
RESULTS_BUCKET   = os.environ["RESULTS_BUCKET"]
CUR_TABLE        = os.environ.get("CUR_TABLE", "cost_and_usage")
REGION           = os.environ.get("AWS_REGION", "us-east-1")

athena = boto3.client("athena", region_name=REGION)


# ── Athena helpers ─────────────────────────────────────────────────────────────

ATHENA_SQL = """
SELECT
  DATE_FORMAT(date(substr(line_item_usage_start_date, 1, 10)), '%Y-%m')  AS month,
  line_item_usage_account_id                         AS account_id,
  bill_payer_account_id                              AS payer_account_id,
  product_region                                     AS region,
  line_item_usage_type                               AS volume_type,
  resource_tags_user_environment                     AS environment,
  resource_tags_user_team                            AS team,
  SUM(line_item_usage_amount)                        AS gb_provisioned,
  SUM(line_item_unblended_cost)                      AS total_cost,
  COUNT(DISTINCT line_item_resource_id)              AS volume_count
FROM {database}.{table}
WHERE
  line_item_product_code   = 'AmazonEC2'
  AND line_item_usage_type LIKE '%EBS:VolumeUsage%'
  AND line_item_line_item_type NOT IN ('Credit', 'Refund')
  AND date(substr(line_item_usage_start_date, 1, 10))
      BETWEEN DATE_ADD('month', -{months}, CURRENT_DATE) AND CURRENT_DATE
  {region_filter}
GROUP BY 1, 2, 3, 4, 5, 6, 7
ORDER BY month DESC, total_cost DESC
"""


def run_athena_query(sql: str) -> list[dict]:
    resp = athena.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Database": ATHENA_DATABASE},
        WorkGroup=ATHENA_WORKGROUP,
        ResultConfiguration={
            "OutputLocation": f"s3://{RESULTS_BUCKET}/results/"
        },
    )
    qid = resp["QueryExecutionId"]

    deadline = time.time() + 55
    while time.time() < deadline:
        status = athena.get_query_execution(QueryExecutionId=qid)
        state  = status["QueryExecution"]["Status"]["State"]
        if state == "SUCCEEDED":
            break
        if state in ("FAILED", "CANCELLED"):
            reason = status["QueryExecution"]["Status"].get("StateChangeReason", "unknown")
            raise RuntimeError(f"Athena query {state}: {reason}")
        time.sleep(1)
    else:
        athena.stop_query_execution(QueryExecutionId=qid)
        raise TimeoutError("Athena query did not complete within 55 s")

    rows, next_token = [], None
    while True:
        kwargs = {"QueryExecutionId": qid, "MaxResults": 1000}
        if next_token:
            kwargs["NextToken"] = next_token
        page = athena.get_query_results(**kwargs)
        rows.extend(page["ResultSet"]["Rows"])
        next_token = page.get("NextToken")
        if not next_token:
            break

    if not rows:
        return []

    headers = [c["VarCharValue"] for c in rows[0]["Data"]]
    return [
        {headers[i]: col.get("VarCharValue", "") for i, col in enumerate(row["Data"])}
        for row in rows[1:]
    ]


# ── Aggregation helpers ────────────────────────────────────────────────────────

def build_monthly_trend(rows: list[dict]) -> list[dict]:
    by_month: dict[str, float] = {}
    for r in rows:
        m = r["month"]
        by_month[m] = by_month.get(m, 0) + float(r.get("total_cost") or 0)
    sorted_months = sorted(by_month)
    if not sorted_months:
        return []
    baseline = sum(by_month[m] for m in sorted_months[:3]) / max(len(sorted_months[:3]), 1)
    return [{"month": m, "spend": round(by_month[m], 2), "baseline": round(baseline, 2)} for m in sorted_months]


def detect_cleanup_start(trend: list[dict]) -> str:
    """Return the first month where spend dropped >5% below baseline, or '' if not detected."""
    if not trend:
        return ""
    baseline = trend[0]["baseline"]
    return next(
        (t["month"] for t in trend if t["spend"] < baseline * 0.95),
        "",  # empty string = no cleanup detected in this window
    )


def build_kpi(trend: list[dict], volumes_deleted: int) -> dict:
    if not trend:
        return {
            "total_saved": 0, "monthly_before": 0, "monthly_after": 0,
            "volumes_deleted": 0, "projected_annual": 0,
        }
    baseline      = trend[0]["baseline"]
    monthly_after = trend[-1]["spend"]
    total_saved   = sum(max(t["baseline"] - t["spend"], 0) for t in trend)
    return {
        "total_saved":      round(total_saved, 2),
        "monthly_before":   round(baseline, 2),
        "monthly_after":    round(monthly_after, 2),
        "volumes_deleted":  volumes_deleted,
        "projected_annual": round(max(baseline - monthly_after, 0) * 12, 2),
    }


def _split_month(month: str, cleanup_start: str, all_months: list[str]) -> str:
    """Return 'pre' or 'post' for a given month. Falls back to midpoint split."""
    if cleanup_start:
        return "pre" if month < cleanup_start else "post"
    if not all_months:
        return "post"
    midpoint = all_months[len(all_months) // 2]
    return "pre" if month < midpoint else "post"


def build_accounts(rows: list[dict], cleanup_start: str) -> list[dict]:
    all_months = sorted({r["month"] for r in rows})
    by_acct: dict[str, dict] = {}
    for r in rows:
        aid   = r["account_id"]
        month = r["month"]
        cost  = float(r.get("total_cost") or 0)
        cnt   = int(r.get("volume_count") or 0)
        if aid not in by_acct:
            by_acct[aid] = {"account_id": aid, "account_name": aid, "ou": "—",
                             "pre": [], "post": [], "volumes_deleted": 0}
        by_acct[aid][_split_month(month, cleanup_start, all_months)].append(cost)
        by_acct[aid]["volumes_deleted"] += cnt

    result = []
    for a in by_acct.values():
        before  = sum(a["pre"])  / max(len(a["pre"]),  1)
        after   = sum(a["post"]) / max(len(a["post"]), 1)
        # Skip accounts where both pre and post are zero — no real data
        if before == 0 and after == 0:
            continue
        savings = max(before - after, 0)
        result.append({
            "account_id":      a["account_id"],
            "account_name":    a["account_name"],
            "ou":              a["ou"],
            "before":          round(before, 2),
            "after":           round(after, 2),
            "savings":         round(savings, 2),
            "pct_reduction":   round(savings / max(before, 1) * 100, 1),
            "volumes_deleted": a["volumes_deleted"],
        })
    return sorted(result, key=lambda x: x["savings"], reverse=True)


def build_regions(rows: list[dict], cleanup_start: str) -> list[dict]:
    all_months = sorted({r["month"] for r in rows})
    by_region: dict[str, dict] = {}
    for r in rows:
        reg   = r.get("region") or "unknown"
        cost  = float(r.get("total_cost") or 0)
        cnt   = int(r.get("volume_count") or 0)
        month = r["month"]
        if reg not in by_region:
            by_region[reg] = {"region": reg, "pre": [], "post": [], "volumes_deleted": 0}
        by_region[reg][_split_month(month, cleanup_start, all_months)].append(cost)
        by_region[reg]["volumes_deleted"] += cnt

    result = []
    for v in by_region.values():
        before  = sum(v["pre"])  / max(len(v["pre"]),  1)
        after   = sum(v["post"]) / max(len(v["post"]), 1)
        savings = max(before - after, 0)
        result.append({
            "region":          v["region"],
            "before":          round(before, 2),
            "after":           round(after, 2),
            "savings":         round(savings, 2),
            "volumes_deleted": v["volumes_deleted"],
        })
    return sorted(result, key=lambda x: x["savings"], reverse=True)


def build_volume_types(rows: list[dict], cleanup_start: str) -> list[dict]:
    price_map  = {"gp2": 0.10, "gp3": 0.08, "io1": 0.125, "io2": 0.125, "st1": 0.045, "sc1": 0.025}
    all_months = sorted({r["month"] for r in rows})
    by_type: dict[str, dict] = {}
    for r in rows:
        vt    = (r.get("volume_type") or "").split(":")[-1].lower().replace("volumeusage.", "")
        cost  = float(r.get("total_cost") or 0)
        month = r["month"]
        if vt not in by_type:
            by_type[vt] = {"pre": [], "post": []}
        by_type[vt][_split_month(month, cleanup_start, all_months)].append(cost)

    result = []
    for vt, d in by_type.items():
        before  = sum(d["pre"])  / max(len(d["pre"]),  1)
        after   = sum(d["post"]) / max(len(d["post"]), 1)
        savings = max(before - after, 0)
        result.append({
            "volume_type":  vt,
            "before":       round(before, 2),
            "after":        round(after, 2),
            "savings":      round(savings, 2),
            "price_per_gb": price_map.get(vt, 0.10),
            "pct_of_total": 0,  # filled in below
        })

    total_savings = sum(x["savings"] for x in result)
    for item in result:
        item["pct_of_total"] = round(item["savings"] / max(total_savings, 1) * 100, 1)

    return sorted(result, key=lambda x: x["savings"], reverse=True)


# ── Main handler ───────────────────────────────────────────────────────────────

def main(event, context):
    params = event.get("queryStringParameters") or {}
    months = int(params.get("months", "18"))
    region = params.get("region", "all")

    region_filter = f"AND product_region = '{region}'" if region and region != "all" else ""

    sql  = ATHENA_SQL.format(database=ATHENA_DATABASE, table=CUR_TABLE, months=months, region_filter=region_filter)
    rows = run_athena_query(sql)

    trend         = build_monthly_trend(rows)
    cleanup_start = detect_cleanup_start(trend)

    # volumes_deleted = fleet size at baseline minus fleet size at latest month.
    # Using volume_count from a single month avoids double-counting across months.
    months_sorted = sorted({r["month"] for r in rows})
    first_month   = months_sorted[0]  if months_sorted else None
    last_month    = months_sorted[-1] if months_sorted else None
    first_count   = sum(int(r.get("volume_count") or 0) for r in rows if r["month"] == first_month)
    last_count    = sum(int(r.get("volume_count") or 0) for r in rows if r["month"] == last_month)
    volumes_deleted = max(first_count - last_count, 0)

    accounts     = build_accounts(rows, cleanup_start)
    volume_types = build_volume_types(rows, cleanup_start)

    # Derive OU savings from accounts (ou field = "—" in Phase 1; Phase 2 enriches this)
    ou_map: dict[str, float] = {}
    for a in accounts:
        ou = a["ou"]
        ou_map[ou] = ou_map.get(ou, 0) + a["savings"]
    ou_savings = [{"ou": ou, "savings": round(s, 2)} for ou, s in sorted(ou_map.items(), key=lambda x: x[1], reverse=True)]

    payload = {
        "kpi":                 build_kpi(trend, volumes_deleted=volumes_deleted),
        "monthly_trend":       trend,
        "cleanup_start_month": cleanup_start,
        "accounts":            accounts,
        "regions":             build_regions(rows, cleanup_start),
        "volume_types":        volume_types,
        "ou_savings":          ou_savings,
        "donut":               [{"name": vt["volume_type"], "value": vt["savings"]} for vt in volume_types],
        "volumes":             [],   # Phase 2 populates this via EC2 DescribeVolumes
    }

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type":                "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(payload),
    }
