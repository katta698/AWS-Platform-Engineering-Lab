"""The service that matters.

Identical in every respect to the two neighbours except DURATION_MS. That
symmetry is deliberate: if these handlers differed in memory, runtime or work
done, the experiment's result could be argued away as a property of the code
rather than of the concurrency pool they share.
"""
import json
import os
import time
import uuid

import boto3

TABLE = os.environ["TABLE"]
SERVICE = os.environ["SERVICE"]
DURATION_S = int(os.environ.get("DURATION_MS", "50")) / 1000.0

_ddb = boto3.resource("dynamodb").Table(TABLE)


def handler(event, context):
    started = time.time()

    # Hold the execution environment open. Concurrency is requests-per-second
    # multiplied by duration, so this sleep is what actually consumes the pool
    # -- a faster handler at the same request rate consumes proportionally
    # less of it.
    time.sleep(DURATION_S)

    key = "%s#%s" % (SERVICE, uuid.uuid4())
    _ddb.put_item(Item={"pk": key, "at": int(started)})

    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({
            "service": SERVICE,
            "key": key,
            "held_ms": round((time.time() - started) * 1000),
            "request_id": context.aws_request_id,
        }),
    }
