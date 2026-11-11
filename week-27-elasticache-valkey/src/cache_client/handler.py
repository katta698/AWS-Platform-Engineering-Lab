"""Issue the same number of requests against three value sizes.

Event: {"size_kb": 1, "requests": 200000}

Returns the request count, bytes moved and the ECPUs those imply, so the
estimate sits beside what CloudWatch and the bill report. ECPUs are billed
on the higher of bytes moved or vCPU time; for a plain GET/SET the byte
dimension wins, which is the point.
"""
import os
import time

import valkey

HOST = os.environ["CACHE_HOST"]
PORT = int(os.environ["CACHE_PORT"])

_client = None


def client():
    global _client
    if _client is None:
        # Serverless requires TLS. ssl_cert_reqs=None because the cache uses
        # an AWS-managed certificate for a private endpoint.
        _client = valkey.Valkey(host=HOST, port=PORT, ssl=True,
                                ssl_cert_reqs=None, socket_timeout=10)
    return _client


def handler(event, context):
    size_kb = int(event.get("size_kb", 1))
    requests = int(event.get("requests", 1000))
    key = "w27:size-%dkb" % size_kb
    payload = b"x" * (size_kb * 1024)

    c = client()
    c.set(key, payload)

    start = time.time()
    for _ in range(requests):
        c.get(key)
    elapsed = time.time() - start

    kb_moved = size_kb * requests
    return {
        "size_kb": size_kb,
        "requests": requests,
        "seconds": round(elapsed, 2),
        "kb_moved": kb_moved,
        # 1 ECPU per KB for a simple read, so this is the floor the byte
        # dimension sets. The bill is the higher of this and vCPU time.
        "ecpus_from_bytes": kb_moved,
        "cost_usd": round(kb_moved / 1_000_000 * 0.0023, 6),
    }
