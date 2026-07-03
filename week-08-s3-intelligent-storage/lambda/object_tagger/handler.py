"""
Object tagger Lambda.

Triggered by SQS (which receives S3 ObjectCreated events).
Inspects the object key and applies content-type tags that lifecycle
rules and Intelligent-Tiering can use for targeted policy application.

Tags applied:
  content-type: logs | data | media | archive | other
  upload-date:  YYYY-MM-DD
"""

import os
import json
import boto3
from datetime import datetime, timezone
from urllib.parse import unquote_plus

BUCKET_NAME = os.environ["BUCKET_NAME"]

# Map key prefix patterns to a content-type tag value
PREFIX_MAP = {
    "logs/":    "logs",
    "data/":    "data",
    "media/":   "media",
    "archive/": "archive",
}

# Map file extension to a content-type tag value (fallback when prefix doesn't match)
EXTENSION_MAP = {
    ".log": "logs", ".gz": "logs", ".json.gz": "logs",
    ".csv": "data", ".json": "data", ".parquet": "data",
    ".jpg": "media", ".jpeg": "media", ".png": "media",
    ".mp4": "media", ".mov": "media",
    ".zip": "archive", ".tar": "archive", ".tar.gz": "archive",
}


def classify_object(key):
    for prefix, tag_value in PREFIX_MAP.items():
        if key.startswith(prefix):
            return tag_value
    for ext, tag_value in EXTENSION_MAP.items():
        if key.lower().endswith(ext):
            return tag_value
    return "other"


def tag_object(s3, bucket, key, content_type_tag):
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    s3.put_object_tagging(
        Bucket=bucket,
        Key=key,
        Tagging={
            "TagSet": [
                {"Key": "content-type", "Value": content_type_tag},
                {"Key": "upload-date",  "Value": today},
            ]
        },
    )


def handler(event, context):
    s3 = boto3.client("s3")
    processed = []
    errors = []

    for record in event.get("Records", []):
        try:
            body = json.loads(record["body"])
            s3_records = body.get("Records", [])

            for s3_record in s3_records:
                bucket = s3_record["s3"]["bucket"]["name"]
                key = unquote_plus(s3_record["s3"]["object"]["key"])

                content_type = classify_object(key)
                tag_object(s3, bucket, key, content_type)
                processed.append({"key": key, "content-type": content_type})

        except Exception as e:
            errors.append({"record": record.get("messageId"), "error": str(e)})

    if errors:
        # Raising causes SQS to retry and eventually DLQ — appropriate for transient failures
        raise RuntimeError(f"Failed to process {len(errors)} record(s): {errors}")

    return {"processed": len(processed), "objects": processed}
