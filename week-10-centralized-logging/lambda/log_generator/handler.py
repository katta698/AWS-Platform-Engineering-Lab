"""Synthetic log generator for the Week 10 centralised logging platform.

Emits structured JSON log lines at weighted INFO/WARN/ERROR levels so the
centralization rule, metric filter, alarm, and dashboard have real traffic
to work with. Runs in the SOURCE account on an EventBridge schedule.
"""

import json
import os
import random
import time

SERVICES = ["checkout", "inventory", "payments", "auth", "shipping"]
OPERATIONS = ["GetItem", "PutOrder", "ChargeCard", "ValidateToken", "CreateLabel"]

INFO_MESSAGES = [
    "request completed",
    "cache hit",
    "downstream call succeeded",
    "session refreshed",
]
WARN_MESSAGES = [
    "retrying downstream call",
    "response time above soft limit",
    "cache miss ratio elevated",
]
ERROR_MESSAGES = [
    "downstream call failed after retries",
    "database connection timeout",
    "unhandled exception in request handler",
]


def _emit(level: str, message: str) -> None:
    line = {
        "level": level,
        "service": random.choice(SERVICES),
        "operation": random.choice(OPERATIONS),
        "message": message,
        "latency_ms": random.randint(5, 900),
        "request_id": f"req-{random.randrange(16**8):08x}",
        "ts": int(time.time() * 1000),
    }
    print(json.dumps(line))


def lambda_handler(event, context):
    lines = int(os.environ.get("LINES_PER_INVOKE", "25"))
    error_rate = int(os.environ.get("ERROR_RATE_PCT", "8"))

    counts = {"INFO": 0, "WARN": 0, "ERROR": 0}
    for _ in range(lines):
        roll = random.randint(1, 100)
        if roll <= error_rate:
            _emit("ERROR", random.choice(ERROR_MESSAGES))
            counts["ERROR"] += 1
        elif roll <= error_rate + 15:
            _emit("WARN", random.choice(WARN_MESSAGES))
            counts["WARN"] += 1
        else:
            _emit("INFO", random.choice(INFO_MESSAGES))
            counts["INFO"] += 1

    return {"emitted": counts}
