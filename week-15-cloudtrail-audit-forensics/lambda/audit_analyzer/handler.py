"""
Daily CloudTrail audit check.

Runs the three "should be zero" queries against the organization trail table and
publishes each result as a CloudWatch custom metric. Alarms live in Terraform and
are all STATIC thresholds -- see the module header in monitoring/main.tf for why
anomaly detection is deliberately absent here.

Why daily and not hourly: the questions are root usage, console sign-in without
MFA, and activity in unused regions. None of those need sub-day latency to be
actionable, and CloudTrail delivers to S3 on roughly a 5-15 minute lag with
occasional longer tails, so a tighter schedule mostly buys re-reading the same
partition. The forensic queries -- who changed this, what did they do -- are not
scheduled at all; they are run by a human after something has happened.

Two behaviours worth knowing before changing anything:

  * Every query is partition-filtered on year/month/day. Athena bills $5/TB
    scanned and this runs forever. An unfiltered query here is a standing
    charge, not a one-off mistake. CloudTrail JSON is verbose and uncompressed
    relative to columnar formats, so it is a worse thing to scan than most.

  * A query returning no rows publishes an explicit 0 rather than skipping the
    metric. A gap and a real zero look identical on a graph and behave very
    differently in an alarm -- a gap leaves the alarm in its previous state
    indefinitely, which is how a broken analyzer passes for a quiet account.
"""

import json
import logging
import os
import time
from datetime import datetime, timezone

import boto3
from botocore.config import Config

logger = logging.getLogger()
logger.setLevel(logging.INFO)

BOTO_CONFIG = Config(retries={"max_attempts": 5, "mode": "standard"})

athena = boto3.client("athena", config=BOTO_CONFIG)
cloudwatch = boto3.client("cloudwatch", config=BOTO_CONFIG)

DATABASE = os.environ["ATHENA_DATABASE"]
TABLE = os.environ["ATHENA_TABLE"]
WORKGROUP = os.environ["ATHENA_WORKGROUP"]
METRIC_NAMESPACE = os.environ.get("METRIC_NAMESPACE", "CloudTrailAudit")
EXPECTED_REGIONS = [
    r.strip() for r in os.environ.get("EXPECTED_REGIONS", "us-east-1").split(",") if r.strip()
]
QUERY_TIMEOUT_SECONDS = int(os.environ.get("QUERY_TIMEOUT_SECONDS", "180"))
POLL_INTERVAL_SECONDS = float(os.environ.get("POLL_INTERVAL_SECONDS", "2"))

QUALIFIED_TABLE = f'"{DATABASE}"."{TABLE}"'

# Partition predicate. Built from concrete date parts so Athena can prune before
# reading anything -- a predicate it cannot evaluate at planning time still
# returns the right answer, after scanning every partition and billing for it.
#
# Uses today and yesterday rather than today alone: a run just after midnight UTC
# would otherwise look at an almost-empty partition and report a reassuring zero
# for a day that had not happened yet.
PARTITION_PREDICATE = """
    (
      (year = date_format(current_date, '%Y')
       AND month = date_format(current_date, '%m')
       AND day = date_format(current_date, '%d'))
      OR
      (year = date_format(current_date - interval '1' day, '%Y')
       AND month = date_format(current_date - interval '1' day, '%m')
       AND day = date_format(current_date - interval '1' day, '%d'))
    )
"""


def build_queries() -> dict:
    """
    The three scheduled checks.

    Each returns a single row of scalars. Keeping result sets tiny is deliberate:
    this function produces numbers for CloudWatch, it does not move data. The
    queries that return real rows for a human live in athena/ and are published
    as named queries.
    """
    where = PARTITION_PREDICATE
    regions = ", ".join(f"'{r}'" for r in EXPECTED_REGIONS)

    return {
        # Root usage. AwsServiceEvent excluded because AWS emits some events
        # attributed to root that no human performed.
        "root_usage": f"""
            SELECT
                COUNT(*)                          AS root_events,
                COUNT(DISTINCT eventname)         AS root_distinct_actions
            FROM {QUALIFIED_TABLE}
            WHERE {where}
              AND useridentity.type = 'Root'
              AND eventtype <> 'AwsServiceEvent'
        """,
        # Successful interactive sign-in with no second factor.
        #
        # mfaauthenticated is a STRING that can also be NULL for federated
        # sign-ins. Testing only `<> 'true'` silently drops the NULL rows, which
        # are exactly the ones worth seeing.
        "console_login_no_mfa": f"""
            SELECT
                COUNT(*)                          AS logins_without_mfa,
                COUNT(DISTINCT COALESCE(useridentity.username, useridentity.arn)) AS distinct_users
            FROM {QUALIFIED_TABLE}
            WHERE {where}
              AND eventsource = 'signin.amazonaws.com'
              AND eventname = 'ConsoleLogin'
              AND responseelements LIKE '%Success%'
              AND (
                    useridentity.sessioncontext.attributes.mfaauthenticated IS NULL
                 OR useridentity.sessioncontext.attributes.mfaauthenticated <> 'true'
              )
        """,
        # Mutating activity outside the regions this estate uses.
        "unexpected_regions": f"""
            SELECT
                COUNT(*)                          AS unexpected_region_events,
                COUNT(DISTINCT region)            AS unexpected_regions
            FROM {QUALIFIED_TABLE}
            WHERE {where}
              AND region NOT IN ({regions})
              AND readonly = 'false'
              AND useridentity.type <> 'AWSService'
        """,
        # Not a "should be zero" metric -- a liveness signal. If the trail stops
        # delivering, every other metric above goes to zero and looks like good
        # news. This is what distinguishes "nothing bad happened" from "nothing
        # arrived at all".
        "trail_liveness": f"""
            SELECT
                COUNT(*)                          AS total_events,
                COUNT(DISTINCT account)           AS accounts_reporting
            FROM {QUALIFIED_TABLE}
            WHERE {where}
        """,
    }


def run_query(sql: str, label: str) -> list:
    """Execute one query and return its rows, or raise on failure/timeout."""
    logger.info("Starting query %s", label)

    execution_id = athena.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Database": DATABASE},
        WorkGroup=WORKGROUP,
    )["QueryExecutionId"]

    deadline = time.time() + QUERY_TIMEOUT_SECONDS
    state = "QUEUED"
    result = None

    while time.time() < deadline:
        result = athena.get_query_execution(QueryExecutionId=execution_id)
        status = result["QueryExecution"]["Status"]
        state = status["State"]
        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        time.sleep(POLL_INTERVAL_SECONDS)

    if state != "SUCCEEDED":
        reason = "timed out waiting for completion"
        scanned = 0
        if result is not None:
            reason = result["QueryExecution"]["Status"].get("StateChangeReason", reason)
            scanned = result["QueryExecution"].get("Statistics", {}).get("DataScannedInBytes", 0)
        # CANCELLED with a scan figure at the workgroup ceiling means the
        # bytes-scanned cutoff fired. That is the guardrail working, not a bug --
        # but it does mean this query needs a tighter partition filter.
        raise RuntimeError(
            f"Query {label} ended in {state}: {reason} "
            f"(execution {execution_id}, scanned {scanned} bytes)"
        )

    scanned = result["QueryExecution"].get("Statistics", {}).get("DataScannedInBytes", 0)
    logger.info("Query %s succeeded, scanned %s bytes", label, scanned)

    paginator = athena.get_paginator("get_query_results")
    rows = []
    for page in paginator.paginate(QueryExecutionId=execution_id):
        rows.extend(page["ResultSet"]["Rows"])
    return rows


def parse_single_row(rows: list) -> dict:
    """
    Turn an Athena result set into {column: value}.

    Row 0 is always the header. A query that matched nothing still returns that
    header, so an absent data row means zero -- not missing.
    """
    if not rows:
        return {}

    headers = [c.get("VarCharValue", "") for c in rows[0]["Data"]]
    if len(rows) < 2:
        return {h: 0.0 for h in headers}

    values = []
    for cell in rows[1]["Data"]:
        raw = cell.get("VarCharValue")
        if raw is None or raw == "":
            values.append(0.0)
            continue
        try:
            values.append(float(raw))
        except ValueError:
            values.append(0.0)

    return dict(zip(headers, values))


def publish_metrics(metrics: dict, timestamp: datetime) -> None:
    """Publish in chunks of 20 -- PutMetricData's per-call limit."""
    data = [
        {"MetricName": name, "Timestamp": timestamp, "Value": value, "Unit": "Count"}
        for name, value in metrics.items()
    ]
    for i in range(0, len(data), 20):
        cloudwatch.put_metric_data(Namespace=METRIC_NAMESPACE, MetricData=data[i : i + 20])
    logger.info("Published %d metrics to %s", len(data), METRIC_NAMESPACE)


def handler(event, context):
    timestamp = datetime.now(timezone.utc)
    queries = build_queries()

    metrics = {}
    failures = {}

    for label, sql in queries.items():
        try:
            parsed = parse_single_row(run_query(sql, label))
            metrics.update(parsed)
            logger.info("Query %s produced: %s", label, json.dumps(parsed))
        except Exception as exc:  # noqa: BLE001 - one bad query must not sink the rest
            logger.exception("Query %s failed", label)
            failures[label] = str(exc)

    if metrics:
        publish_metrics(metrics, timestamp)

    result = {
        "timestamp": timestamp.isoformat(),
        "expected_regions": EXPECTED_REGIONS,
        "metrics_published": len(metrics),
        "metrics": metrics,
        "failures": failures,
    }

    if failures:
        # Raise so Lambda records an error and the async retry / DLQ path engages.
        # Without this a permanently broken query would be invisible: the function
        # would succeed every day while publishing nothing, and the alarms would
        # sit at their last known value forever.
        raise RuntimeError(f"{len(failures)} of {len(queries)} queries failed: {failures}")

    return result
