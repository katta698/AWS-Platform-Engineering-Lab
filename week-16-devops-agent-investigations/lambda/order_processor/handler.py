"""
A small workload that exists to be broken in a known way.

The lab needs a failure whose true cause is established BEFORE the agent is
asked about it, so the agent's conclusion can be marked rather than admired.
This is the smallest thing that produces a realistic one.

It reads a configuration value from SSM Parameter Store and writes a record to
S3. Both are ordinary, both are things a real service does, and either can be
broken by changing a permission rather than by changing code -- which is the
interesting case. A code change leaves an obvious diff; a permission change
leaves a working deployment that has quietly stopped working.

The failure mode this is built for: revoke ssm:GetParameter, and the function
starts throwing AccessDeniedException on a code path that has not changed. The
symptom is "orders stopped processing". The cause is an IAM edit. Whether the
agent gets from one to the other is the whole question.
"""
import json
import os
import time
import uuid

import boto3

PARAM_NAME = os.environ["CONFIG_PARAM_NAME"]
BUCKET = os.environ["RECORDS_BUCKET"]

ssm = boto3.client("ssm")
s3 = boto3.client("s3")


def handler(event, context):
    started = time.time()

    # Deliberately NOT wrapped in a try/except that swallows the error. A
    # workload that hides its own failure gives the agent nothing to find, and
    # the point here is to leave a real, attributable error in the logs.
    config = ssm.get_parameter(Name=PARAM_NAME)["Parameter"]["Value"]

    record = {
        "order_id": str(uuid.uuid4()),
        "processed_at": int(started),
        "config": config,
    }
    key = "orders/%s.json" % record["order_id"]
    s3.put_object(Bucket=BUCKET, Key=key, Body=json.dumps(record).encode())

    duration_ms = int((time.time() - started) * 1000)
    print(json.dumps({"msg": "order processed", "key": key, "duration_ms": duration_ms}))

    return {"ok": True, "key": key, "duration_ms": duration_ms}
