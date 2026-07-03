"""
Daily S3 storage cost reporter.

Queries CloudWatch BucketSizeBytes metrics for each storage class,
calculates what the bill would be if everything stayed in Standard,
compares to the actual tiered cost, and publishes a savings report to SNS.

CloudWatch S3 metrics have a 24-hour delay and are emitted once per day.
"""

import os
import json
import boto3
from datetime import datetime, timedelta, timezone

BUCKET_NAME = os.environ["BUCKET_NAME"]
SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
REGION = os.environ.get("AWS_REGION_NAME", os.environ.get("AWS_DEFAULT_REGION", "us-east-1"))

# Prices per GB/month (us-east-1, verified 2026-06-30 — check aws.amazon.com/s3/pricing/)
STORAGE_PRICES = {
    "StandardStorage":                    0.023,
    "StandardIAStorage":                  0.0125,
    "IntelligentTieringFAStorage":        0.023,   # Frequent Access — same as Standard
    "IntelligentTieringIAStorage":        0.0125,  # Infrequent Access
    "IntelligentTieringAIAStorage":       0.004,   # Archive Instant Access
    "IntelligentTieringAAStorage":        0.00099, # Archive Access (Deep Archive equivalent)
    "GlacierInstantRetrievalStorage":     0.004,
    "GlacierStorage":                     0.0036,
    "DeepArchiveStorage":                 0.00099,
    "ReducedRedundancyStorage":           0.023,   # Legacy, same price as Standard
    "OneZoneIAStorage":                   0.01,
}

BYTES_PER_GB = 1024 ** 3


def get_bucket_size_by_storage_type(cw, bucket_name):
    """Return {storage_type: size_in_bytes} for the given bucket."""
    storage_types = list(STORAGE_PRICES.keys())
    now = datetime.now(timezone.utc)
    # S3 metrics are daily; look back 2 days to ensure we catch the latest data point
    start = now - timedelta(days=2)

    sizes = {}
    for storage_type in storage_types:
        response = cw.get_metric_statistics(
            Namespace="AWS/S3",
            MetricName="BucketSizeBytes",
            Dimensions=[
                {"Name": "BucketName", "Value": bucket_name},
                {"Name": "StorageType", "Value": storage_type},
            ],
            StartTime=start,
            EndTime=now,
            Period=86400,
            Statistics=["Average"],
        )
        datapoints = response.get("Datapoints", [])
        if datapoints:
            latest = max(datapoints, key=lambda d: d["Timestamp"])
            sizes[storage_type] = latest["Average"]

    return sizes


def calculate_costs(sizes):
    """Return (actual_cost, standard_only_cost, total_bytes) for a sizes dict."""
    total_bytes = sum(sizes.values())
    actual_cost = 0.0
    for storage_type, size_bytes in sizes.items():
        size_gb = size_bytes / BYTES_PER_GB
        price = STORAGE_PRICES.get(storage_type, 0.023)
        actual_cost += size_gb * price

    standard_only_cost = (total_bytes / BYTES_PER_GB) * STORAGE_PRICES["StandardStorage"]
    return actual_cost, standard_only_cost, total_bytes


def format_bytes(b):
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if b < 1024:
            return f"{b:.2f} {unit}"
        b /= 1024
    return f"{b:.2f} PB"


def build_report(bucket_name, sizes, actual_cost, standard_only_cost, total_bytes):
    savings = standard_only_cost - actual_cost
    savings_pct = (savings / standard_only_cost * 100) if standard_only_cost > 0 else 0

    lines = [
        f"S3 Storage Cost Report — {datetime.now(timezone.utc).strftime('%Y-%m-%d')}",
        f"Bucket: {bucket_name}",
        f"Region: {REGION}",
        "",
        f"{'Storage Class':<35} {'Size':>12} {'Monthly Cost':>14}",
        "-" * 65,
    ]

    for storage_type, size_bytes in sorted(sizes.items(), key=lambda x: -x[1]):
        size_gb = size_bytes / BYTES_PER_GB
        price = STORAGE_PRICES.get(storage_type, 0.023)
        cost = size_gb * price
        lines.append(f"{storage_type:<35} {format_bytes(size_bytes):>12} ${cost:>13.4f}")

    lines += [
        "-" * 65,
        f"{'TOTAL':<35} {format_bytes(total_bytes):>12} ${actual_cost:>13.4f}",
        "",
        f"If everything stayed in Standard:      ${standard_only_cost:.4f}/month",
        f"Actual cost with tiering:              ${actual_cost:.4f}/month",
        f"Monthly savings:                       ${savings:.4f} ({savings_pct:.1f}%)",
        "",
        "Prices: us-east-1 as of 2026-06-30 — verify at https://aws.amazon.com/s3/pricing/",
        "Note: CloudWatch S3 metrics have a 24-hour delay. Data may reflect yesterday's state.",
    ]

    if not sizes:
        lines = [
            f"S3 Storage Cost Report — {datetime.now(timezone.utc).strftime('%Y-%m-%d')}",
            f"Bucket: {bucket_name}",
            "",
            "No storage data available yet. CloudWatch S3 metrics take 24 hours to appear",
            "after a bucket is created or first populated.",
        ]

    return "\n".join(lines)


def handler(event, context):
    cw = boto3.client("cloudwatch", region_name=REGION)
    sns = boto3.client("sns", region_name=REGION)

    sizes = get_bucket_size_by_storage_type(cw, BUCKET_NAME)
    actual_cost, standard_only_cost, total_bytes = calculate_costs(sizes)
    report = build_report(BUCKET_NAME, sizes, actual_cost, standard_only_cost, total_bytes)

    sns.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject=f"S3 Storage Report — {BUCKET_NAME} — {datetime.now(timezone.utc).strftime('%Y-%m-%d')}",
        Message=report,
    )

    return {
        "statusCode": 200,
        "bucket": BUCKET_NAME,
        "total_bytes": total_bytes,
        "actual_cost_usd": round(actual_cost, 4),
        "standard_only_cost_usd": round(standard_only_cost, 4),
        "savings_usd": round(standard_only_cost - actual_cost, 4),
    }
