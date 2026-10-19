#!/usr/bin/env python3
"""
generate_mock_cur.py
--------------------
Generates synthetic CUR 2.0 Parquet files that mimic real AWS billing data
for EBS volumes across a large multi-account organisation.

Scale:
    - 500 accounts across 15 OUs
    - ~5,000 EC2 instances, each with 1-3 EBS volumes (~10,000 volumes total)
    - 18 months of data (Jan 2025 → Jun 2026)
    - Cleanup event starts Sep 2025: unattached + stale gp2 volumes removed
    - Spend drops ~35% over 3 months post-cleanup

Usage:
    pip install pyarrow pandas boto3
    python generate_mock_cur.py                        # write files locally
    python generate_mock_cur.py --upload --bucket my-cur-bucket
"""

import argparse
import os
import random
import uuid
from datetime import datetime, timezone

import boto3
import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq

# ── Org structure ─────────────────────────────────────────────────────────────

PAYER_ACCOUNT = "000000000000"

# 15 OUs with realistic names and account counts
OUS = [
    {"name": "Production",        "prefix": "prod",       "count": 80,  "ec2_per_acct": (30, 60)},
    {"name": "Production-Data",   "prefix": "prod-data",  "count": 40,  "ec2_per_acct": (20, 50)},
    {"name": "Production-ML",     "prefix": "prod-ml",    "count": 20,  "ec2_per_acct": (10, 30)},
    {"name": "Staging",           "prefix": "staging",    "count": 50,  "ec2_per_acct": (8, 20)},
    {"name": "Development",       "prefix": "dev",        "count": 100, "ec2_per_acct": (3, 10)},
    {"name": "Sandbox",           "prefix": "sandbox",    "count": 80,  "ec2_per_acct": (1, 5)},
    {"name": "Security",          "prefix": "security",   "count": 10,  "ec2_per_acct": (5, 15)},
    {"name": "Shared-Services",   "prefix": "shared",     "count": 20,  "ec2_per_acct": (10, 25)},
    {"name": "Network",           "prefix": "network",    "count": 10,  "ec2_per_acct": (5, 15)},
    {"name": "Logging",           "prefix": "logging",    "count": 10,  "ec2_per_acct": (5, 20)},
    {"name": "Analytics",         "prefix": "analytics",  "count": 30,  "ec2_per_acct": (10, 30)},
    {"name": "FinTech",           "prefix": "fintech",    "count": 20,  "ec2_per_acct": (15, 40)},
    {"name": "Healthcare",        "prefix": "healthcare", "count": 10,  "ec2_per_acct": (10, 25)},
    {"name": "Legacy",            "prefix": "legacy",     "count": 10,  "ec2_per_acct": (20, 60)},  # lots of old gp2 volumes
    {"name": "Archive",           "prefix": "archive",    "count": 10,  "ec2_per_acct": (5, 15)},
]

REGIONS = [
    "us-east-1",
    "us-west-2",
    "eu-west-1",
    "eu-central-1",
    "ap-southeast-1",
    "ap-northeast-1",
]

# Region weight — us-east-1 dominates like real orgs
REGION_WEIGHTS = [0.40, 0.20, 0.15, 0.10, 0.10, 0.05]

# Volume type configs: (usage_type_suffix, price_per_gb_month, size_range_gb, deletable_prob)
# deletable_prob = chance a given volume will be targeted during cleanup
VOLUME_TYPES = [
    ("EBS:VolumeUsage.gp2",  0.10,  (20,  500),  0.55),   # old standard; primary cleanup target
    ("EBS:VolumeUsage.gp3",  0.08,  (20,  300),  0.20),   # newer, fewer orphans
    ("EBS:VolumeUsage.io1",  0.125, (100, 2000), 0.10),   # expensive, usually attached
    ("EBS:VolumeUsage.io2",  0.125, (100, 2000), 0.08),
    ("EBS:VolumeUsage.st1",  0.045, (125, 16000),0.25),   # throughput; often orphaned
    ("EBS:VolumeUsage.sc1",  0.025, (125, 16000),0.30),   # cold; frequent orphan
]

# EC2 instance type → typical root volume size
INSTANCE_VOLUME_PROFILES = [
    ("t3.micro",    "gp3",  8,   0),    # (instance_type, root_type, root_gb, extra_data_gb)
    ("t3.small",    "gp3",  20,  0),
    ("t3.medium",   "gp3",  30,  0),
    ("t3.large",    "gp3",  50,  100),
    ("m5.large",    "gp3",  50,  200),
    ("m5.xlarge",   "gp3",  100, 500),
    ("m5.2xlarge",  "gp3",  100, 1000),
    ("r5.large",    "gp3",  50,  200),
    ("r5.xlarge",   "gp3",  100, 500),
    ("c5.xlarge",   "gp3",  50,  0),
    ("c5.2xlarge",  "gp3",  50,  200),
    ("i3.large",    "gp2",  50,  475),  # storage-optimised; often old gp2
    ("i3.xlarge",   "gp2",  50,  950),
    ("p3.2xlarge",  "io1",  100, 500),  # GPU — io1 data disks
    ("d3.xlarge",   "st1",  50,  2000), # dense storage — st1
]

CLEANUP_START = datetime(2025, 9, 1, tzinfo=timezone.utc)
MONTHS        = pd.date_range("2025-01-01", periods=18, freq="MS", tz="UTC")
OUTPUT_DIR    = "./mock_cur"


# ── Build account roster ──────────────────────────────────────────────────────

def build_accounts() -> list[dict]:
    accounts = []
    acct_num = 100000000001
    for ou in OUS:
        for i in range(1, ou["count"] + 1):
            accounts.append({
                "id":           str(acct_num),
                "name":         f"{ou['prefix']}-{i:03d}",
                "ou":           ou["name"],
                "env":          "prod" if "prod" in ou["name"].lower() else
                                "stg"  if "stag" in ou["name"].lower() else
                                "dev",
                "team":         ou["prefix"].split("-")[0],
                "ec2_min":      ou["ec2_per_acct"][0],
                "ec2_max":      ou["ec2_per_acct"][1],
            })
            acct_num += 1
    return accounts


# ── Build volume roster ───────────────────────────────────────────────────────

def make_volume_id():
    return "vol-" + uuid.uuid4().hex[:17]

def pick_region():
    return random.choices(REGIONS, weights=REGION_WEIGHTS, k=1)[0]

def build_volume_roster(accounts: list[dict]) -> tuple[list[dict], list[dict]]:
    """
    Returns:
      base_volumes  — volumes that exist at the start of the simulation
      new_volumes   — volumes created during the simulation (churn)

    Lifecycle model (mirrors real orgs):
      - Cleanup automation runs monthly from CLEANUP_START, deleting orphans gradually
        over ~9 months (not a one-time cliff drop)
      - New orphan volumes appear every month as engineers terminate EC2s without
        cleaning up their disks — partially offsetting the savings
      - Net result: spend trends downward with natural month-to-month variation
    """
    base_volumes = []
    new_volumes  = []
    type_lookup  = {vt[0].split(".")[-1]: vt for vt in VOLUME_TYPES}
    cleanup_month_list = [m for m in MONTHS if m >= pd.Timestamp(CLEANUP_START)]

    for acct in accounts:
        region      = pick_region()
        n_instances = random.randint(acct["ec2_min"], acct["ec2_max"])

        # ── Attached volumes (EC2-backed) ──────────────────────────────────────
        for _ in range(n_instances):
            profile = random.choice(INSTANCE_VOLUME_PROFILES)
            _, root_type, root_gb, extra_gb = profile

            vt_cfg = type_lookup.get(root_type, VOLUME_TYPES[1])
            base_volumes.append(_make_volume(acct, region, vt_cfg, root_gb, attached=True))

            if extra_gb > 0:
                data_type = "gp2" if random.random() < 0.4 else "gp3"
                vt_cfg = type_lookup.get(data_type, VOLUME_TYPES[0])
                base_volumes.append(_make_volume(acct, region, vt_cfg, extra_gb, attached=True))

        # ── Pre-existing orphan volumes ────────────────────────────────────────
        n_orphans = max(1, int(n_instances * 0.15))
        for _ in range(n_orphans):
            vt_cfg  = random.choices(VOLUME_TYPES, weights=[4, 1, 1, 1, 2, 2], k=1)[0]
            size_gb = random.randint(*vt_cfg[2])
            vol = _make_volume(acct, region, vt_cfg, size_gb, attached=False)
            vol["deletable_prob"] = min(vol["deletable_prob"] * 1.8, 0.95)
            base_volumes.append(vol)

        # ── Newly created orphans per month (churn) ────────────────────────────
        # ~0.5% of instances terminated each month without disk cleanup.
        # Kept low so cleanup savings outpace churn (net spend trends down).
        for month in MONTHS:
            n_new_orphans = max(0, int(n_instances * 0.005 * random.uniform(0.5, 1.5)))
            for _ in range(n_new_orphans):
                vt_cfg  = random.choices(VOLUME_TYPES, weights=[3, 2, 1, 1, 2, 1], k=1)[0]
                size_gb = random.randint(*vt_cfg[2])
                vol = _make_volume(acct, region, vt_cfg, size_gb, attached=False)
                vol["create_month"] = month
                # Newly orphaned volumes: cleanup automation picks them up 1-4 months later
                if month >= pd.Timestamp(CLEANUP_START) and random.random() < 0.75:
                    months_until_cleanup = random.randint(1, 4)
                    try:
                        cur_idx    = cleanup_month_list.index(month)
                        future_idx = cur_idx + months_until_cleanup
                        vol["delete_month"] = cleanup_month_list[future_idx] if future_idx < len(cleanup_month_list) else None
                    except ValueError:
                        vol["delete_month"] = None
                else:
                    vol["delete_month"] = None
                new_volumes.append(vol)

    # ── Apply gradual cleanup to base volumes ──────────────────────────────────
    # Spread across 9 months (not 3) — cleanup automation finds orphans gradually
    for vol in base_volumes:
        if random.random() < vol["deletable_prob"]:
            # Weight earlier months higher (first sweep catches the most)
            n = len(cleanup_month_list)
            weights = [max(1, 6 - i // 2) for i in range(n)]
            vol["delete_month"] = random.choices(cleanup_month_list, weights=weights, k=1)[0]
        else:
            vol["delete_month"] = None

    return base_volumes, new_volumes


def _make_volume(acct: dict, region: str, vt_cfg: tuple, size_gb: int, attached: bool) -> dict:
    _, price, size_range, base_deletable = vt_cfg
    actual_size = max(size_range[0], min(size_gb + random.randint(-10, 20), size_range[1]))
    # Attached volumes much less likely to be deleted
    deletable_prob = base_deletable * (0.3 if attached else 1.0)
    return {
        "volume_id":       make_volume_id(),
        "account_id":      acct["id"],
        "account_name":    acct["name"],
        "ou":              acct["ou"],
        "region":          region,
        "usage_type":      vt_cfg[0],
        "price_per_gb":    price,
        "size_gb":         actual_size,
        "attached":        attached,
        "deletable_prob":  deletable_prob,
        "delete_month":    None,
        "env":             acct["env"],
        "team":            acct["team"],
    }


# ── Build one month of CUR rows ───────────────────────────────────────────────

def build_month_rows(month: pd.Timestamp, all_volumes: list[dict]) -> list[dict]:
    rows = []
    # ±3% natural cost variation per month (price fluctuations, partial-month billing)
    noise = random.uniform(0.97, 1.03)

    for vol in all_volumes:
        # Skip if not yet created (churn volumes have a create_month)
        if vol.get("create_month") is not None and month < vol["create_month"]:
            continue
        # Skip if already deleted
        if vol["delete_month"] is not None and month >= vol["delete_month"]:
            continue

        hours     = ((month + pd.DateOffset(months=1)) - month).days * 24
        usage_amt = vol["size_gb"] * hours
        cost      = vol["size_gb"] * vol["price_per_gb"] * noise

        rows.append({
            "line_item_usage_start_date":     month.isoformat(),
            "line_item_usage_account_id":     vol["account_id"],
            "bill_payer_account_id":          PAYER_ACCOUNT,
            "product_region":                 vol["region"],
            "line_item_usage_type":           f"{vol['region']}-{vol['usage_type']}",
            "line_item_product_code":         "AmazonEC2",
            "line_item_line_item_type":       "Usage",
            "line_item_resource_id":          vol["volume_id"],
            "line_item_usage_amount":         round(usage_amt, 4),
            "line_item_unblended_cost":       round(cost, 6),
            "resource_tags_user_environment": vol["env"],
            "resource_tags_user_team":        vol["team"],
        })
    return rows


# ── Write Parquet ─────────────────────────────────────────────────────────────

SCHEMA = pa.schema([
    pa.field("line_item_usage_start_date",       pa.string()),
    pa.field("line_item_usage_account_id",        pa.string()),
    pa.field("bill_payer_account_id",             pa.string()),
    pa.field("product_region",                    pa.string()),
    pa.field("line_item_usage_type",              pa.string()),
    pa.field("line_item_product_code",            pa.string()),
    pa.field("line_item_line_item_type",          pa.string()),
    pa.field("line_item_resource_id",             pa.string()),
    pa.field("line_item_usage_amount",            pa.float64()),
    pa.field("line_item_unblended_cost",          pa.float64()),
    pa.field("resource_tags_user_environment",    pa.string()),
    pa.field("resource_tags_user_team",           pa.string()),
])

def write_parquet(rows: list[dict], path: str):
    df    = pd.DataFrame(rows)
    table = pa.Table.from_pandas(df, schema=SCHEMA, preserve_index=False)
    pq.write_table(table, path, compression="snappy")
    print(f"  wrote {len(rows):>7,} rows → {path}")


# ── Upload to S3 ──────────────────────────────────────────────────────────────

def upload_to_s3(local_dir: str, bucket: str, prefix: str, profile: str = None):
    session = boto3.Session(profile_name=profile) if profile else boto3.Session()
    s3 = session.client("s3")
    for fname in sorted(os.listdir(local_dir)):
        if not fname.endswith(".parquet"):
            continue
        local_path = os.path.join(local_dir, fname)
        s3_key     = f"{prefix}/{fname}"
        print(f"  uploading s3://{bucket}/{s3_key}")
        s3.upload_file(local_path, bucket, s3_key)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Generate synthetic CUR Parquet files")
    parser.add_argument("--upload",  action="store_true", help="Upload to S3 after generating")
    parser.add_argument("--bucket",  default="",          help="S3 bucket name (required with --upload)")
    parser.add_argument("--prefix",  default="cur/synthetic-report", help="S3 key prefix")
    parser.add_argument("--out-dir", default=OUTPUT_DIR,  help="Local output directory")
    parser.add_argument("--profile", default=None,        help="AWS profile name")
    args = parser.parse_args()

    if args.upload and not args.bucket:
        parser.error("--bucket is required when --upload is set")

    os.makedirs(args.out_dir, exist_ok=True)

    print("Building account roster...")
    accounts = build_accounts()
    print(f"  {len(accounts)} accounts across {len(OUS)} OUs")

    print("\nBuilding volume roster (EC2 instances + EBS volumes)...")
    base_volumes, new_volumes = build_volume_roster(accounts)
    all_volumes   = base_volumes + new_volumes
    total_vols    = len(base_volumes)
    attached_vols = sum(1 for v in base_volumes if v["attached"])
    orphan_vols   = total_vols - attached_vols
    deletable     = sum(1 for v in base_volumes if v["delete_month"] is not None)
    print(f"  {total_vols:,} base volumes (existing at simulation start)")
    print(f"  {attached_vols:,} attached to EC2 instances")
    print(f"  {orphan_vols:,} unattached / orphaned")
    print(f"  {deletable:,} targeted for cleanup ({deletable/total_vols*100:.0f}%)")
    print(f"  {len(new_volumes):,} new orphan volumes created via monthly churn")

    print(f"\nGenerating {len(MONTHS)} months of CUR data...\n")
    total_rows = 0
    monthly_costs = []
    for month in MONTHS:
        label = month.strftime("%Y-%m")
        rows  = build_month_rows(month, all_volumes)
        path  = os.path.join(args.out_dir, f"cur_{label}.parquet")
        write_parquet(rows, path)
        cost  = sum(r["line_item_unblended_cost"] for r in rows)
        total_rows    += len(rows)
        monthly_costs.append((label, len(rows), cost))

    print(f"\nTotal CUR rows generated: {total_rows:,}")
    print(f"Files written to:         {os.path.abspath(args.out_dir)}/\n")

    print("Monthly EBS spend summary:")
    print(f"  {'Month':<10}  {'Volumes':>8}  {'EBS Cost':>14}")
    print(f"  {'-'*40}")
    for label, n_rows, cost in monthly_costs:
        marker = " ← cleanup starts" if label == CLEANUP_START.strftime("%Y-%m") else ""
        print(f"  {label:<10}  {n_rows:>8,}  ${cost:>12,.2f}{marker}")

    pre_months  = [c for lbl, _, c in monthly_costs if lbl < CLEANUP_START.strftime("%Y-%m")]
    post_months = [c for lbl, _, c in monthly_costs[-3:]]
    if pre_months and post_months:
        avg_pre  = sum(pre_months)  / len(pre_months)
        avg_post = sum(post_months) / len(post_months)
        savings  = avg_pre - avg_post
        print(f"\n  Avg monthly spend (pre-cleanup):  ${avg_pre:>10,.2f}")
        print(f"  Avg monthly spend (post-cleanup): ${avg_post:>10,.2f}")
        print(f"  Monthly savings achieved:         ${savings:>10,.2f}  ({savings/avg_pre*100:.1f}% reduction)")

    if args.upload:
        print(f"\nUploading to s3://{args.bucket}/{args.prefix}/")
        upload_to_s3(args.out_dir, args.bucket, args.prefix, profile=args.profile)
        print("\nDone. Next steps:")
        print("  1. Run the Glue crawler to register/update the table schema")
        print("  2. Query Athena: SELECT COUNT(*) FROM <db>.<table>")
        print("  3. Open the dashboard and select 'Last 18 months'")


if __name__ == "__main__":
    random.seed(42)
    main()
