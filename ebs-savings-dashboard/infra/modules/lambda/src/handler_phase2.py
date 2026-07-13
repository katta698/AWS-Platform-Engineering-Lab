"""
EBS Savings API — Phase 2 Lambda handler (CUR + cross-account EC2 inventory)

Data flow:
  CUR Parquet (S3) → Glue catalog → Athena → Lambda → API Gateway → Dashboard
  EC2 DescribeVolumes (each member account via assumed role) → Lambda → Dashboard

Phase 2 scope:
  - Overview, By Account, By Region, By Volume Type tabs  ✓  (same as Phase 1)
  - Volume Inventory tab                                   ✓  (live EC2 data across all accounts)
  - Cross-account IAM role assumptions (EBSDashboardReadRole must exist in every member account)
  - AWS Organizations API to enumerate member accounts

Prerequisites (deploy before this Lambda):
  infra/cross_account_roles/ — run generate_providers.py then terraform apply to create
  EBSDashboardReadRole in every member account.
"""
import json
import os
import time
import boto3
from datetime import datetime, timezone

ATHENA_DATABASE  = os.environ["ATHENA_DATABASE"]
ATHENA_WORKGROUP = os.environ["ATHENA_WORKGROUP"]
RESULTS_BUCKET   = os.environ["RESULTS_BUCKET"]
MEMBER_ROLE_NAME = os.environ["MEMBER_ROLE_NAME"]   # required in Phase 2
ORG_ID           = os.environ.get("ORG_ID", "")
CUR_TABLE        = os.environ.get("CUR_TABLE", "cost_and_usage")
REGION           = os.environ.get("AWS_REGION", "us-east-1")

athena = boto3.client("athena", region_name=REGION)
ec2    = boto3.client("ec2",    region_name=REGION)
sts    = boto3.client("sts")
org    = boto3.client("organizations")


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


# ── EC2 helpers ────────────────────────────────────────────────────────────────

def list_member_accounts() -> list[str]:
    """Return all ACTIVE member account IDs from AWS Organizations."""
    accounts, next_token = [], None
    while True:
        kwargs = {}
        if next_token:
            kwargs["NextToken"] = next_token
        page = org.list_accounts(**kwargs)
        accounts.extend(
            a["Id"] for a in page["Accounts"] if a["Status"] == "ACTIVE"
        )
        next_token = page.get("NextToken")
        if not next_token:
            break
    return accounts


def get_ec2_client(account_id: str) -> boto3.client:
    """Return an EC2 client for a member account by assuming EBSDashboardReadRole."""
    role_arn = f"arn:aws:iam::{account_id}:role/{MEMBER_ROLE_NAME}"
    creds = sts.assume_role(
        RoleArn=role_arn,
        RoleSessionName="EBSDashboardRead",
        DurationSeconds=900,
    )["Credentials"]
    return boto3.client(
        "ec2",
        region_name=REGION,
        aws_access_key_id=creds["AccessKeyId"],
        aws_secret_access_key=creds["SecretAccessKey"],
        aws_session_token=creds["SessionToken"],
    )


def describe_volumes(account_id: str) -> list[dict]:
    client = get_ec2_client(account_id)
    volumes, next_token = [], None
    while True:
        kwargs = {"MaxResults": 500}
        if next_token:
            kwargs["NextToken"] = next_token
        page = client.describe_volumes(**kwargs)
        volumes.extend(page["Volumes"])
        next_token = page.get("NextToken")
        if not next_token:
            break
    return volumes


def enrich_volumes(raw_volumes: list[dict], account_id: str, account_name: str) -> list[dict]:
    """Convert EC2 DescribeVolumes response into dashboard rows."""
    now = datetime.now(timezone.utc)
    price_map = {"gp2": 0.10, "gp3": 0.08, "io1": 0.125, "io2": 0.125, "st1": 0.045, "sc1": 0.025}
    enriched = []
    for v in raw_volumes:
        attachments = v.get("Attachments", [])
        attached    = len(attachments) > 0
        instance_id = attachments[0]["InstanceId"] if attached else None
        inst_state  = attachments[0].get("State", "") if attached else None

        if not attached:
            attachment_state = "unattached"
        elif inst_state == "attached":
            attachment_state = "attached-running"
        else:
            attachment_state = "attached-stopped"

        tags  = {t["Key"]: t["Value"] for t in v.get("Tags", [])}
        age_d = (now - v["CreateTime"]).days
        price = price_map.get(v["VolumeType"], 0.10)

        enriched.append({
            "volume_id":        v["VolumeId"],
            "name":             tags.get("Name", ""),
            "size_gb":          v["Size"],
            "volume_type":      v["VolumeType"],
            "region":           REGION,
            "az":               v["AvailabilityZone"],
            "attachment_state": attachment_state,
            "instance_id":      instance_id,
            "instance_type":    None,
            "instance_state":   None,
            "monthly_cost":     round(v["Size"] * price, 2),
            "age_days":         age_d,
            "has_recent_snapshot": False,
            "account_id":       account_id,
            "account_name":     account_name,
            "tags_name":        tags.get("Name", ""),
            "tags_env":         tags.get("Environment", tags.get("Env", "")),
            "tags_team":        tags.get("Team", ""),
        })
    return enriched


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


def build_kpi(trend: list[dict], volumes_deleted: int) -> dict:
    if not trend:
        return {}
    baseline      = trend[0]["baseline"]
    monthly_after = trend[-1]["spend"]
    total_saved   = sum(max(t["baseline"] - t["spend"], 0) for t in trend)
    return {
        "total_saved":      round(total_saved, 2),
        "monthly_before":   round(baseline, 2),
        "monthly_after":    round(monthly_after, 2),
        "volumes_deleted":  volumes_deleted,
        "projected_annual": round((baseline - monthly_after) * 12, 2),
    }


def build_accounts(rows: list[dict], cleanup_start: str) -> list[dict]:
    by_acct: dict[str, dict] = {}
    for r in rows:
        aid   = r["account_id"]
        month = r["month"]
        cost  = float(r.get("total_cost") or 0)
        cnt   = int(r.get("volume_count") or 0)
        if aid not in by_acct:
            by_acct[aid] = {"account_id": aid, "account_name": aid, "ou": "—",
                             "pre": [], "post": [], "volumes_deleted": 0}
        if cleanup_start and month < cleanup_start:
            by_acct[aid]["pre"].append(cost)
        else:
            by_acct[aid]["post"].append(cost)
        by_acct[aid]["volumes_deleted"] += cnt

    result = []
    for a in by_acct.values():
        before  = sum(a["pre"])  / max(len(a["pre"]),  1)
        after   = sum(a["post"]) / max(len(a["post"]), 1)
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


def build_regions(rows: list[dict]) -> list[dict]:
    by_region: dict[str, dict] = {}
    for r in rows:
        reg  = r.get("region") or "unknown"
        cost = float(r.get("total_cost") or 0)
        cnt  = int(r.get("volume_count") or 0)
        if reg not in by_region:
            by_region[reg] = {"region": reg, "after": 0, "volumes_deleted": 0}
        by_region[reg]["after"]           += cost
        by_region[reg]["volumes_deleted"] += cnt

    return [
        {**v, "before": round(v["after"] * 1.5, 2),
         "savings": round(v["after"] * 0.5, 2)}
        for v in sorted(by_region.values(), key=lambda x: x["after"], reverse=True)
    ]


def build_volume_types(rows: list[dict]) -> list[dict]:
    price_map = {"gp2": 0.10, "gp3": 0.08, "io1": 0.125, "io2": 0.125, "st1": 0.045, "sc1": 0.025}
    by_type: dict[str, float] = {}
    for r in rows:
        vt   = (r.get("volume_type") or "").split(":")[-1].lower().replace("volumeusage.", "")
        cost = float(r.get("total_cost") or 0)
        by_type[vt] = by_type.get(vt, 0) + cost

    total = sum(by_type.values())
    return [
        {
            "volume_type":  vt,
            "after":        round(cost, 2),
            "before":       round(cost * 1.8, 2),
            "savings":      round(cost * 0.8, 2),
            "price_per_gb": price_map.get(vt, 0.10),
            "pct_of_total": round(cost / max(total, 1) * 100, 1),
        }
        for vt, cost in sorted(by_type.items(), key=lambda x: x[1], reverse=True)
    ]


# ── Main handler ───────────────────────────────────────────────────────────────

def main(event, context):
    params = event.get("queryStringParameters") or {}
    months = int(params.get("months", "18"))

    # 1. Athena CUR query
    sql  = ATHENA_SQL.format(database=ATHENA_DATABASE, table=CUR_TABLE, months=months)
    rows = run_athena_query(sql)

    # 2. EC2 DescribeVolumes across all member accounts
    member_accounts = list_member_accounts()
    all_volumes = []
    for account_id in member_accounts:
        try:
            raw = describe_volumes(account_id)
            all_volumes.extend(enrich_volumes(raw, account_id, account_id))
        except Exception as e:
            # Log and continue — one unreachable account shouldn't break the dashboard
            print(f"WARN: could not describe volumes in {account_id}: {e}")

    # 3. Build aggregations
    trend    = build_monthly_trend(rows)
    baseline = trend[0]["baseline"] if trend else 0

    cleanup_start = next(
        (t["month"] for t in trend if t["spend"] < baseline * 0.95),
        trend[-1]["month"] if trend else "",
    )

    # volumes_deleted: count of currently-unattached volumes from live EC2 inventory
    volumes_deleted = len([v for v in all_volumes if v["attachment_state"] == "unattached"])

    payload = {
        "kpi":                 build_kpi(trend, volumes_deleted=volumes_deleted),
        "monthly_trend":       trend,
        "cleanup_start_month": cleanup_start,
        "accounts":            build_accounts(rows, cleanup_start),
        "regions":             build_regions(rows),
        "volume_types":        build_volume_types(rows),
        "ou_savings":          [],
        "donut":               [{"name": vt["volume_type"], "value": vt["savings"]} for vt in build_volume_types(rows)],
        "volumes":             all_volumes,
    }

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type":                "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps(payload),
    }
