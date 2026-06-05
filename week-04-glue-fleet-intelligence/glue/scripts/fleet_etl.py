"""
fleet_etl.py — AWS Glue PySpark ETL script.

Reads raw SSM Resource Data Sync output from S3 (JSON),
transforms it into a clean curated Parquet dataset partitioned
by ingest_date and account_id.

Tables produced in curated zone:
  - patch_compliance   : per-instance patch compliance state
  - inventory          : per-instance OS + hardware info
  - applications       : per-instance installed software list
"""

import sys
import json
from datetime import datetime, timezone

from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.context import SparkContext
from pyspark.sql import functions as F
from pyspark.sql.types import (
    StructType, StructField, StringType, IntegerType, TimestampType, BooleanType
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

SOURCE_BUCKET  = args["SOURCE_BUCKET"]
DEST_BUCKET    = args["DEST_BUCKET"]
DATABASE       = args["GLUE_DATABASE"]
ENVIRONMENT    = args["ENVIRONMENT"]
REPORT_SCOPE   = args["REPORT_SCOPE"]   # all | patch | inventory

ingest_date = datetime.now(timezone.utc).strftime("%Y-%m-%d")
print(f"[fleet_etl] Starting | scope={REPORT_SCOPE} | date={ingest_date}")


# ─────────────────────────────────────────────────────────────────────────────
# Helper: write curated Parquet
# ─────────────────────────────────────────────────────────────────────────────
def write_curated(df, table_name: str):
    path = f"s3://{DEST_BUCKET}/fleet/{table_name}/ingest_date={ingest_date}/"
    (df
     .repartition(1)
     .write
     .mode("overwrite")
     .parquet(path))
    print(f"[fleet_etl] Written {df.count()} rows → {path}")


# ─────────────────────────────────────────────────────────────────────────────
# 1. PATCH COMPLIANCE
# ─────────────────────────────────────────────────────────────────────────────
if REPORT_SCOPE in ("all", "patch"):
    print("[fleet_etl] Processing patch compliance data...")
    try:
        raw_patch = spark.read.json(
            f"s3://{SOURCE_BUCKET}/ssm/*/PatchCompliance/*/data/"
        )

        patch_df = (
            raw_patch
            .select(
                F.col("resourceId").alias("instance_id"),
                F.col("resourceType").alias("resource_type"),
                F.col("complianceType").alias("compliance_type"),
                F.col("status").alias("compliance_status"),
                F.col("overallSeverity").alias("severity"),
                F.col("executionSummary.executionTime").cast(TimestampType()).alias("last_patch_time"),
                F.col("accountId").alias("account_id"),
                F.col("region"),
                F.lit(ENVIRONMENT).alias("environment"),
                F.lit(ingest_date).alias("ingest_date"),
            )
            .withColumn(
                "missing_patch_count",
                F.when(F.col("compliance_status") == "NON_COMPLIANT", F.lit(1)).otherwise(F.lit(0))
            )
            .withColumn("instance_name",
                F.regexp_extract(F.col("instance_id"), r"i-([a-f0-9]+)", 0)
            )
        )

        write_curated(patch_df, "patch_compliance")
    except Exception as e:
        print(f"[fleet_etl] WARNING: patch compliance processing failed: {e}")


# ─────────────────────────────────────────────────────────────────────────────
# 2. INVENTORY (OS, hardware)
# ─────────────────────────────────────────────────────────────────────────────
if REPORT_SCOPE in ("all", "inventory"):
    print("[fleet_etl] Processing inventory data...")
    try:
        raw_inventory = spark.read.json(
            f"s3://{SOURCE_BUCKET}/ssm/*/AWS:InstanceInformation/*/data/"
        )

        inventory_df = (
            raw_inventory
            .select(
                F.col("resourceId").alias("instance_id"),
                F.col("content.PlatformName").alias("platform_name"),
                F.col("content.PlatformVersion").alias("platform_version"),
                F.col("content.PlatformType").alias("platform_type"),
                F.col("content.AgentVersion").alias("ssm_agent_version"),
                F.col("content.InstanceType").alias("instance_type"),
                F.col("content.IPAddress").alias("ip_address"),
                F.col("content.ComputerName").alias("computer_name"),
                F.col("content.AssociationStatus").alias("association_status"),
                F.col("accountId").alias("account_id"),
                F.col("region"),
                F.lit(ENVIRONMENT).alias("environment"),
                F.lit(ingest_date).alias("ingest_date"),
            )
        )

        write_curated(inventory_df, "inventory")
    except Exception as e:
        print(f"[fleet_etl] WARNING: inventory processing failed: {e}")


# ─────────────────────────────────────────────────────────────────────────────
# 3. APPLICATIONS (installed software)
# ─────────────────────────────────────────────────────────────────────────────
if REPORT_SCOPE in ("all", "inventory"):
    print("[fleet_etl] Processing application inventory...")
    try:
        raw_apps = spark.read.json(
            f"s3://{SOURCE_BUCKET}/ssm/*/AWS:Application/*/data/"
        )

        apps_df = (
            raw_apps
            .select(
                F.col("resourceId").alias("instance_id"),
                F.explode(F.col("content")).alias("app"),
                F.col("accountId").alias("account_id"),
                F.col("region"),
                F.lit(ENVIRONMENT).alias("environment"),
                F.lit(ingest_date).alias("ingest_date"),
            )
            .select(
                "instance_id",
                F.col("app.Name").alias("name"),
                F.col("app.Version").alias("version"),
                F.col("app.Publisher").alias("publisher"),
                F.col("app.InstalledTime").alias("installed_time"),
                "account_id",
                "region",
                "environment",
                "ingest_date",
            )
        )

        write_curated(apps_df, "applications")
    except Exception as e:
        print(f"[fleet_etl] WARNING: application inventory processing failed: {e}")


# ─────────────────────────────────────────────────────────────────────────────
# 4. FLEET SUMMARY (aggregated — one row per instance)
# ─────────────────────────────────────────────────────────────────────────────
print("[fleet_etl] Building fleet summary...")
try:
    patch_summary = spark.read.parquet(
        f"s3://{DEST_BUCKET}/fleet/patch_compliance/ingest_date={ingest_date}/"
    )
    inv_summary = spark.read.parquet(
        f"s3://{DEST_BUCKET}/fleet/inventory/ingest_date={ingest_date}/"
    )

    fleet_summary = (
        patch_summary.alias("p")
        .join(inv_summary.alias("i"), on="instance_id", how="left")
        .select(
            F.col("p.instance_id"),
            F.col("i.computer_name").alias("instance_name"),
            F.col("i.platform_name"),
            F.col("i.platform_version"),
            F.col("i.instance_type"),
            F.col("p.compliance_status"),
            F.col("p.severity"),
            F.col("p.last_patch_time"),
            F.col("p.missing_patch_count"),
            F.col("p.environment"),
            F.col("p.account_id"),
            F.col("p.region"),
            F.lit(ingest_date).alias("ingest_date"),
        )
    )

    write_curated(fleet_summary, "fleet_summary")
except Exception as e:
    print(f"[fleet_etl] WARNING: fleet summary failed: {e}")

print("[fleet_etl] Done.")
job.commit()
