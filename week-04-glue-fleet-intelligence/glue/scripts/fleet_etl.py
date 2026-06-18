"""
fleet_etl.py — AWS Glue PySpark ETL script.

SSM Resource Data Sync writes NDJSON files at paths like:
  ssm/AWS:ComplianceSummary/accountid=<acct>/region=<region>/resourcetype=<type>/<instance>.json
  ssm/AWS:InstanceInformation/accountid=<acct>/region=<region>/resourcetype=<type>/<instance>.json
  ssm/AWS:Application/accountid=<acct>/region=<region>/resourcetype=<type>/<instance>.json

NOTE: The colon in folder names (AWS:ComplianceSummary) breaks Spark/Hadoop URI parsing.
We use boto3 to list and read files directly, bypassing the URI parser issue.
"""

import sys
import json
import re
import traceback
from datetime import datetime, timezone

import boto3

from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import (
    StructType, StructField, StringType, IntegerType, TimestampType, Row
)

# ── Job args ──────────────────────────────────────────────────────────────────
args = getResolvedOptions(sys.argv, [
    "JOB_NAME",
    "SOURCE_BUCKET",
    "DEST_BUCKET",
    "GLUE_DATABASE",
    "ENVIRONMENT",
    "TICKET_ID",
    "REPORT_SCOPE",
])

sc          = SparkContext()
glueContext = GlueContext(sc)
spark       = glueContext.spark_session
job         = Job(glueContext)
job.init(args["JOB_NAME"], args)

SOURCE_BUCKET = args["SOURCE_BUCKET"]
DEST_BUCKET   = args["DEST_BUCKET"]
ENVIRONMENT   = args["ENVIRONMENT"]
REPORT_SCOPE  = args["REPORT_SCOPE"]

ingest_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
print(f"[fleet_etl] Starting | scope={REPORT_SCOPE} | date={ingest_date} | source={SOURCE_BUCKET}")

s3_client = boto3.client("s3")


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
def read_ssm_prefix(bucket, prefix):
    """
    Read all non-empty JSON files under an S3 prefix using boto3.
    Returns a list of dicts with _account_id and _region injected from the path.
    Uses boto3 to avoid Spark URI parsing issues with colons in S3 folder names.
    """
    records = []
    paginator = s3_client.get_paginator("list_objects_v2")

    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        for obj in page.get("Contents", []):
            if obj["Size"] == 0:
                continue
            key = obj["Key"]

            # Extract partition values from path
            acct_match   = re.search(r"accountid=([^/]+)", key)
            region_match = re.search(r"region=([^/]+)", key)
            account_id   = acct_match.group(1)   if acct_match   else ""
            region       = region_match.group(1)  if region_match else ""

            body = (
                s3_client.get_object(Bucket=bucket, Key=key)["Body"]
                .read()
                .decode("utf-8", errors="replace")
            )

            for line in body.strip().split("\n"):
                line = line.strip()
                if not line:
                    continue
                try:
                    record = json.loads(line)
                    record["_account_id"] = account_id
                    record["_region"]     = region
                    records.append(record)
                except json.JSONDecodeError:
                    pass

    print(f"[fleet_etl] read_ssm_prefix({prefix}): {len(records)} records")
    return records


def write_curated(df, table_name):
    """Write DataFrame to curated S3 as Parquet."""
    count = df.count()
    if count == 0:
        print(f"[fleet_etl] WARNING: 0 rows for {table_name} — skipping")
        return
    path = f"s3://{DEST_BUCKET}/fleet/{table_name}/ingest_date={ingest_date}/"
    df.repartition(1).write.mode("overwrite").parquet(path)
    print(f"[fleet_etl] Written {count} rows → {path}")


# ─────────────────────────────────────────────────────────────────────────────
# 1. PATCH COMPLIANCE  (AWS:ComplianceSummary — filter ComplianceType == Patch)
# ─────────────────────────────────────────────────────────────────────────────
if REPORT_SCOPE in ("all", "patch"):
    print("[fleet_etl] Processing patch compliance...")
    try:
        records = read_ssm_prefix(SOURCE_BUCKET, "ssm/AWS:ComplianceSummary/")

        # Filter to Patch compliance only
        patch_records = [r for r in records if r.get("ComplianceType") == "Patch"]
        print(f"[fleet_etl] Patch records after filter: {len(patch_records)}")

        if patch_records:
            raw_df = spark.createDataFrame(patch_records)

            patch_df = raw_df.select(
                F.col("resourceId").alias("instance_id"),
                F.col("ComplianceType").alias("compliance_type"),
                F.col("Status").alias("compliance_status"),
                F.col("OverallSeverity").alias("severity"),
                F.col("ExecutionTime").cast(TimestampType()).alias("last_patch_time"),
                F.col("PatchGroup").alias("patch_group") if "PatchGroup" in raw_df.columns
                    else F.lit(None).cast(StringType()).alias("patch_group"),
                F.col("CompliantCriticalCount").cast(IntegerType()).alias("compliant_critical"),
                F.col("CompliantHighCount").cast(IntegerType()).alias("compliant_high"),
                F.col("NonCompliantCriticalCount").cast(IntegerType()).alias("non_compliant_critical"),
                F.col("NonCompliantHighCount").cast(IntegerType()).alias("non_compliant_high"),
                F.col("NonCompliantMediumCount").cast(IntegerType()).alias("non_compliant_medium"),
                F.col("captureTime").cast(TimestampType()).alias("capture_time"),
                F.col("_account_id").alias("account_id"),
                F.col("_region").alias("region"),
                F.lit(ENVIRONMENT).alias("environment"),
                F.lit(ingest_date).alias("ingest_date"),
            ).withColumn(
                "missing_patch_count",
                F.coalesce(F.col("non_compliant_critical"), F.lit(0))
                + F.coalesce(F.col("non_compliant_high"), F.lit(0))
                + F.coalesce(F.col("non_compliant_medium"), F.lit(0))
            )

            write_curated(patch_df, "patch_compliance")
        else:
            print("[fleet_etl] No Patch compliance records found")

    except Exception as e:
        print(f"[fleet_etl] ERROR: patch compliance failed: {e}")
        traceback.print_exc()


# ─────────────────────────────────────────────────────────────────────────────
# 2. INVENTORY  (AWS:InstanceInformation)
# ─────────────────────────────────────────────────────────────────────────────
if REPORT_SCOPE in ("all", "inventory"):
    print("[fleet_etl] Processing inventory...")
    try:
        records = read_ssm_prefix(SOURCE_BUCKET, "ssm/AWS:InstanceInformation/")

        if records:
            raw_df = spark.createDataFrame(records)
            cols   = raw_df.columns

            def opt(field, alias):
                return F.col(field).alias(alias) if field in cols \
                    else F.lit(None).cast(StringType()).alias(alias)

            inventory_df = raw_df.select(
                F.col("resourceId").alias("instance_id"),
                opt("InstanceStatus",  "instance_status"),
                opt("PlatformName",    "platform_name"),
                opt("PlatformType",    "platform_type"),
                opt("PlatformVersion", "platform_version"),
                opt("InstanceType",    "instance_type"),
                opt("IPAddress",       "ip_address"),
                opt("ComputerName",    "computer_name"),
                opt("AgentVersion",    "ssm_agent_version"),
                F.col("captureTime").cast(TimestampType()).alias("capture_time"),
                F.col("_account_id").alias("account_id"),
                F.col("_region").alias("region"),
                F.lit(ENVIRONMENT).alias("environment"),
                F.lit(ingest_date).alias("ingest_date"),
            )

            write_curated(inventory_df, "inventory")
        else:
            print("[fleet_etl] No inventory records found")

    except Exception as e:
        print(f"[fleet_etl] ERROR: inventory failed: {e}")
        traceback.print_exc()


# ─────────────────────────────────────────────────────────────────────────────
# 3. APPLICATIONS  (AWS:Application — one line per installed package)
# ─────────────────────────────────────────────────────────────────────────────
if REPORT_SCOPE in ("all", "inventory"):
    print("[fleet_etl] Processing applications...")
    try:
        records = read_ssm_prefix(SOURCE_BUCKET, "ssm/AWS:Application/")

        if records:
            raw_df = spark.createDataFrame(records)
            cols   = raw_df.columns

            def opt(field, alias):
                return F.col(field).alias(alias) if field in cols \
                    else F.lit(None).cast(StringType()).alias(alias)

            apps_df = raw_df.select(
                F.col("resourceId").alias("instance_id"),
                F.col("Name").alias("name"),
                F.col("Version").alias("version"),
                opt("Publisher",       "publisher"),
                opt("InstalledTime",   "installed_time"),
                opt("Architecture",    "architecture"),
                opt("ApplicationType", "application_type"),
                F.col("_account_id").alias("account_id"),
                F.col("_region").alias("region"),
                F.lit(ENVIRONMENT).alias("environment"),
                F.lit(ingest_date).alias("ingest_date"),
            )

            write_curated(apps_df, "applications")
        else:
            print("[fleet_etl] No application records found")

    except Exception as e:
        print(f"[fleet_etl] ERROR: applications failed: {e}")
        traceback.print_exc()


# ─────────────────────────────────────────────────────────────────────────────
# 4. FLEET SUMMARY  (join patch + inventory)
# ─────────────────────────────────────────────────────────────────────────────
print("[fleet_etl] Building fleet summary...")
try:
    patch_df = spark.read.parquet(
        f"s3://{DEST_BUCKET}/fleet/patch_compliance/ingest_date={ingest_date}/"
    )
    inv_df = spark.read.parquet(
        f"s3://{DEST_BUCKET}/fleet/inventory/ingest_date={ingest_date}/"
    )

    fleet_summary = (
        patch_df.alias("p")
        .join(inv_df.alias("i"), on="instance_id", how="left")
        .select(
            F.col("p.instance_id"),
            F.col("i.computer_name").alias("instance_name"),
            F.col("i.platform_name"),
            F.col("i.platform_version"),
            F.col("i.instance_type"),
            F.col("i.instance_status"),
            F.col("p.compliance_status"),
            F.col("p.severity"),
            F.col("p.last_patch_time"),
            F.col("p.missing_patch_count"),
            F.col("p.patch_group"),
            F.col("p.environment"),
            F.col("p.account_id"),
            F.col("p.region"),
            F.lit(ingest_date).alias("ingest_date"),
        )
    )

    write_curated(fleet_summary, "fleet_summary")

except Exception as e:
    print(f"[fleet_etl] WARNING: fleet summary failed: {e}")
    traceback.print_exc()

print("[fleet_etl] Done.")
job.commit()
