"""
Hourly flow log analyzer.

Runs a small set of aggregate queries against the flow log table and publishes the
results as CloudWatch custom metrics. CloudWatch anomaly detection then decides
what counts as unusual, rather than this code carrying a hardcoded idea of normal.

Why Lambda and not Glue or Step Functions: the work is a handful of Athena API
calls, a poll, and a PutMetricData on result sets of a few dozen rows. It finishes
in seconds, holds no state between runs, and runs once an hour. A Glue job would
pay Spark startup and a one-minute DPU minimum to do arithmetic on almost nothing;
Step Functions would orchestrate a workflow that has no branches. If this ever
grows into a real transform over the raw partitions, that calculus flips and
Lambda's 15-minute ceiling becomes a wall.

Two behaviours worth knowing about before changing anything here:

  * Every query is partition-filtered. Athena bills $5 per TB scanned, and this
    runs 24 times a day forever. An unfiltered query here is a standing charge,
    not a one-off mistake.

  * A query returning zero rows publishes an explicit 0, it does not skip the
    metric. A missing datapoint and a real zero look identical on a graph but
    behave differently in an alarm -- a gap leaves the alarm in its previous
    state indefinitely, which is how a broken analyzer passes for a quiet network.
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
METRIC_NAMESPACE = os.environ.get("METRIC_NAMESPACE", "FlowLogIntelligence")
LOOKBACK_HOURS = int(os.environ.get("LOOKBACK_HOURS", "2"))
QUERY_TIMEOUT_SECONDS = int(os.environ.get("QUERY_TIMEOUT_SECONDS", "120"))
POLL_INTERVAL_SECONDS = float(os.environ.get("POLL_INTERVAL_SECONDS", "2"))

QUALIFIED_TABLE = f'"{DATABASE}"."{TABLE}"'

# Partition predicate shared by every query below.
#
# Built from concrete date parts rather than a function over the partition
# columns, so Athena can prune partitions before reading anything. A predicate
# Athena cannot evaluate at planning time still returns the right answer -- after
# scanning every partition and billing for all of it.
PARTITION_PREDICATE = """
    concat(year, '-', month, '-', day) >= date_format(
        current_timestamp - interval '{hours}' hour, '%Y-%m-%d')
    AND from_unixtime("end") >= current_timestamp - interval '{hours}' hour
"""


def _partition_filter() -> str:
    return PARTITION_PREDICATE.format(hours=LOOKBACK_HOURS)


def build_queries() -> dict:
    """
    The metric queries.

    Each returns a single row of scalars. Keeping the result sets tiny is
    deliberate: this function's job is to produce numbers for CloudWatch, not to
    move data. Investigation queries that return real rows live in athena/ and are
    published as named queries for humans to run.
    """
    where = _partition_filter()

    return {
        # Overall volume. The baseline for the anomaly band -- this is the
        # metric that answers "is the network doing more than it usually does".
        "traffic_volume": f"""
            SELECT
                COALESCE(SUM(bytes), 0)                                    AS total_bytes,
                COALESCE(SUM(packets), 0)                                  AS total_packets,
                COUNT(*)                                                   AS flow_records,
                COUNT(DISTINCT srcaddr)                                    AS distinct_sources
            FROM {QUALIFIED_TABLE}
            WHERE {where}
        """,
        # NAT-bound egress only. Tracked separately from total volume because it
        # is the portion that carries a per-GB charge -- total traffic can be
        # flat while the billed share of it climbs.
        #
        # Filters on next_hop_interface_type, NOT traffic_path. The first version
        # used `traffic_path = 2` and published a permanent zero: measured at the
        # sending instance's ENI, NAT-bound traffic records traffic_path 1 ("same
        # VPC"), and the value 8 appears later on the NAT's own ENI where there is
        # no instance tag. traffic_path 2 never appeared in real data at all.
        #
        # This is also why the filter is on the sender's hop rather than the NAT's:
        # the same bytes are visible at both capture points, and counting both
        # would double the cost figure.
        "nat_egress": f"""
            SELECT
                COALESCE(SUM(bytes), 0)                                    AS nat_bytes,
                COUNT(*)                                                   AS nat_flows
            FROM {QUALIFIED_TABLE}
            WHERE {where}
              AND action = 'ACCEPT'
              AND flow_direction = 'egress'
              AND next_hop_interface_type = 'nat_gateway'
        """,
        # Rejected traffic volume. Expected to be non-zero at all times on any
        # internet-reachable address; the anomaly band is what makes it useful.
        "rejected_traffic": f"""
            SELECT
                COUNT(*)                                                   AS reject_count,
                COUNT(DISTINCT srcaddr)                                    AS distinct_reject_sources
            FROM {QUALIFIED_TABLE}
            WHERE {where}
              AND action = 'REJECT'
        """,
        # Sources exhibiting scan-shaped fan-out. Alarmed on a static threshold,
        # not an anomaly band: "some port scanning is normal for this VPC" is not
        # a baseline worth learning.
        "port_scan_candidates": f"""
            SELECT
                COUNT(*)                                                   AS scanner_count
            FROM (
                SELECT srcaddr
                FROM {QUALIFIED_TABLE}
                WHERE {where}
                  AND action = 'REJECT'
                  AND flow_direction = 'ingress'
                GROUP BY srcaddr, dstaddr
                HAVING COUNT(DISTINCT dstport) >= 20
            )
        """,
    }


def run_query(sql: str, label: str) -> list:
    """Execute one query and return its rows, or raise on failure/timeout."""
    logger.info("Starting query %s", label)

    response = athena.start_query_execution(
        QueryString=sql,
        QueryExecutionContext={"Database": DATABASE},
        WorkGroup=WORKGROUP,
    )
    execution_id = response["QueryExecutionId"]

    deadline = time.time() + QUERY_TIMEOUT_SECONDS
    state = "QUEUED"

    while time.time() < deadline:
        result = athena.get_query_execution(QueryExecutionId=execution_id)
        status = result["QueryExecution"]["Status"]
        state = status["State"]

        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break

        time.sleep(POLL_INTERVAL_SECONDS)

    if state != "SUCCEEDED":
        reason = status.get("StateChangeReason", "no reason given")
        stats = result["QueryExecution"].get("Statistics", {})
        scanned = stats.get("DataScannedInBytes", 0)
        # A CANCELLED state with a scan figure at the workgroup ceiling means the
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

    The first row is always the header. A query that matched nothing still
    returns that header, so an empty data section means zero -- not missing.
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
        {
            "MetricName": name,
            "Timestamp": timestamp,
            "Value": value,
            "Unit": "Bytes" if name.endswith("_bytes") else "Count",
        }
        for name, value in metrics.items()
    ]

    for i in range(0, len(data), 20):
        cloudwatch.put_metric_data(
            Namespace=METRIC_NAMESPACE,
            MetricData=data[i : i + 20],
        )

    logger.info("Published %d metrics to %s", len(data), METRIC_NAMESPACE)


def handler(event, context):
    timestamp = datetime.now(timezone.utc)
    queries = build_queries()

    metrics = {}
    failures = {}

    for label, sql in queries.items():
        try:
            rows = run_query(sql, label)
            parsed = parse_single_row(rows)
            metrics.update(parsed)
            logger.info("Query %s produced: %s", label, json.dumps(parsed))
        except Exception as exc:  # noqa: BLE001 - one bad query must not sink the rest
            # Deliberately not re-raised here. One failing query should still let
            # the others publish; raising at the end is what routes to the DLQ.
            logger.exception("Query %s failed", label)
            failures[label] = str(exc)

    if metrics:
        publish_metrics(metrics, timestamp)

    # A derived metric: what the NAT-path bytes in this window would cost if the
    # window repeated for a month. Published as a metric so it can be alarmed and
    # graphed rather than recomputed by every consumer.
    if "nat_bytes" in metrics:
        windows_per_month = (24 / LOOKBACK_HOURS) * 30
        projected = (metrics["nat_bytes"] / 1073741824.0) * 0.045 * windows_per_month
        publish_metrics({"projected_monthly_nat_usd": round(projected, 4)}, timestamp)

    result = {
        "timestamp": timestamp.isoformat(),
        "metrics_published": len(metrics),
        "metrics": metrics,
        "failures": failures,
    }

    if failures:
        # Raise so Lambda records an error and the async retry / DLQ path engages.
        # Without this, a permanently broken query would be invisible: the
        # function would succeed every hour while publishing nothing.
        raise RuntimeError(f"{len(failures)} of {len(queries)} queries failed: {failures}")

    return result
