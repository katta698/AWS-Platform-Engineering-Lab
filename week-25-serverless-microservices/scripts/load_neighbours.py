#!/usr/bin/env python3
"""Hold a fixed number of neighbour requests in flight, from one machine.

WHY THIS EXISTS (2026-10-29)
----------------------------
Run 1 was supposed to exhaust the account's 1,000-concurrency pool and did not
get close: CloudWatch measured a peak of 319 concurrent executions and zero
throttles on every function. The arithmetic the handler itself states --
concurrency = requests per second x duration -- was never in doubt. The client
was.

`run-experiment.py` starts one thread per request. To hold 1,200 ten-second
requests open it would need 1,200 live threads, created at 120 a second, and
CPython does not do that: it managed about 13 requests per second per
neighbour, so the neighbours occupied ~300 slots instead of ~1,200. The
experiment measured a laptop's thread scheduler, not Lambda's pool.

So this driver does the one thing that matters differently: it works in
CONCURRENCY, not in request rate. N coroutines, each holding one request open
at a time on a kept-alive connection. N in flight is the definition of N
concurrent Lambda executions, so the number you ask for is the number you get,
and asyncio carries a few thousand of them on one thread.

It generates neighbour load ONLY. checkout stays with run-experiment.py, whose
recording is the evidence -- this process must not touch the measurement.
"""
from __future__ import annotations

import argparse
import asyncio
import ssl
import sys
import time
from collections import Counter
from urllib.parse import urlparse

STATS = Counter()


async def worker(host: str, port: int, path: str, ctx, stop_at: float) -> None:
    """One slot: keep exactly one request in flight until the deadline."""
    body = b"{}"
    head = (
        "POST %s HTTP/1.1\r\n"
        "Host: %s\r\n"
        "content-type: application/json\r\n"
        "content-length: %d\r\n"
        "connection: keep-alive\r\n\r\n" % (path, host, len(body))
    ).encode()

    reader = writer = None
    try:
        while time.time() < stop_at:
            try:
                if writer is None:
                    reader, writer = await asyncio.open_connection(host, port, ssl=ctx)
                writer.write(head + body)
                await writer.drain()

                status_line = await reader.readuntil(b"\r\n")
                status = int(status_line.split()[1])
                length, chunked = 0, False
                while True:
                    line = await reader.readuntil(b"\r\n")
                    if line == b"\r\n":
                        break
                    low = line.lower()
                    if low.startswith(b"content-length:"):
                        length = int(line.split(b":")[1])
                    elif low.startswith(b"transfer-encoding:") and b"chunked" in low:
                        chunked = True
                if chunked:
                    while True:
                        size = int((await reader.readuntil(b"\r\n")).strip(), 16)
                        if size == 0:
                            await reader.readuntil(b"\r\n")
                            break
                        await reader.readexactly(size + 2)
                elif length:
                    await reader.readexactly(length)

                STATS[status] += 1
            except Exception:
                # A throttled or reset connection is a real datapoint, not a
                # crash. Record it, drop the socket, and take the slot again.
                STATS["error"] += 1
                if writer is not None:
                    try:
                        writer.close()
                    except Exception:
                        pass
                writer = None
                await asyncio.sleep(0.2)
    finally:
        if writer is not None:
            try:
                writer.close()
            except Exception:
                pass


async def main_async(args) -> int:
    u = urlparse(args.endpoint)
    host = u.hostname
    port = u.port or (443 if u.scheme == "https" else 80)
    ctx = ssl.create_default_context() if u.scheme == "https" else None

    if args.start_after:
        print("waiting %ds so the recorder gets a clean baseline first"
              % args.start_after, flush=True)
        await asyncio.sleep(args.start_after)

    stop_at = time.time() + args.seconds
    routes = args.routes.split(",")
    print("holding %d concurrent per route across %s for %ds"
          % (args.concurrency, routes, args.seconds), flush=True)

    tasks = [
        asyncio.create_task(worker(host, port, "/" + r.strip(), ctx, stop_at))
        for r in routes for _ in range(args.concurrency)
    ]

    async def ticker():
        while time.time() < stop_at:
            await asyncio.sleep(10)
            print("  t+%3ds  %s" % (int(args.seconds - (stop_at - time.time())),
                                    dict(STATS)), flush=True)

    t = asyncio.create_task(ticker())
    await asyncio.gather(*tasks, return_exceptions=True)
    t.cancel()
    print("neighbour load finished:", dict(STATS), flush=True)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--endpoint", required=True)
    ap.add_argument("--routes", default="reports,exports")
    ap.add_argument("--concurrency", type=int, default=600,
                    help="in-flight requests PER ROUTE = Lambda concurrency held")
    ap.add_argument("--seconds", type=int, default=180)
    ap.add_argument("--start-after", type=int, default=0)
    args = ap.parse_args()
    return asyncio.run(main_async(args))


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    raise SystemExit(main())
