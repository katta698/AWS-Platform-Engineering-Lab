#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Drive load at the neighbours, and record what happens to checkout.

    python scripts/run-experiment.py --label run1-unprotected
    python scripts/run-experiment.py --label run2-protected

WHAT IT MEASURES, AND WHY FROM THE CLIENT SIDE
----------------------------------------------
checkout is called at a steady, modest rate throughout -- the traffic a real
service would be carrying while something else goes wrong. The neighbours are
then ramped until the account's unreserved concurrency pool is exhausted.

The number that matters is checkout's client-observed success rate, not the
neighbours'. A throttled Lambda never starts: no log line, no exception inside
the handler, nothing for the application to catch. From inside checkout the
incident is invisible. From the caller it is a 502. So the caller is where the
measurement has to be taken.

CloudWatch is sampled alongside, because the client view says THAT checkout
failed and the metrics say WHY -- concurrency climbing, pool filling, throttles
beginning only once it is full.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
TF = ROOT / "terraform" / "environments" / "dev"


def tf_output(name: str):
    out = subprocess.run(["terraform", "-chdir=" + str(TF), "output", "-json", name],
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise SystemExit("terraform output %s failed:\n%s" % (name, out.stderr[-400:]))
    return json.loads(out.stdout)


class Caller(threading.Thread):
    """Fires requests at one route and records every status it gets back."""

    def __init__(self, url: str, rps: float, stop: threading.Event, label: str):
        super().__init__(daemon=True)
        self.url, self.rps, self.stop, self.label = url, rps, stop, label
        self.results = Counter()
        self.lock = threading.Lock()

    def _one(self):
        req = urllib.request.Request(self.url, data=b"{}",
                                     headers={"content-type": "application/json"},
                                     method="POST")
        try:
            with urllib.request.urlopen(req, timeout=35) as r:
                code = r.status
        except urllib.error.HTTPError as e:
            code = e.code
        except Exception:
            code = 0            # connection refused, timeout, reset
        with self.lock:
            self.results[code] += 1

    def snapshot_and_reset(self):
        with self.lock:
            s = dict(self.results)
            self.results.clear()
        return s

    def run(self):
        interval = 1.0 / self.rps if self.rps else 1.0
        while not self.stop.is_set():
            threading.Thread(target=self._one, daemon=True).start()
            time.sleep(interval)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", required=True,
                    help="run1-unprotected or run2-protected")
    ap.add_argument("--checkout-rps", type=float, default=20,
                    help="steady, modest. The traffic a real service carries.")
    ap.add_argument("--neighbour-rps", type=float, default=120,
                    help="per neighbour, ramped on at --ramp-at")
    ap.add_argument("--seconds", type=int, default=240)
    ap.add_argument("--ramp-at", type=int, default=60,
                    help="seconds of clean baseline before the neighbours start")
    args = ap.parse_args()

    base = tf_output("api_endpoint")
    fns = tf_output("function_names")
    region = tf_output("region")
    protected = tf_output("protect_checkout")

    print("endpoint  : %s" % base)
    print("region    : %s" % region)
    print("checkout  : %s" % ("RESERVED concurrency (run 2)" if protected
                              else "no reservation -- shares the pool (run 1)"))
    print()

    # Refuse to mislabel a run. The CSV outlives the session; a run2 file
    # recorded against unprotected infrastructure would be worse than no file.
    if args.label.startswith("run2") and not protected:
        raise SystemExit("REFUSING: --label says run2 but protect_checkout is false.\n"
                         "  Apply with protect_checkout=true first.")
    if args.label.startswith("run1") and protected:
        raise SystemExit("REFUSING: --label says run1 but protect_checkout is true.")

    stop = threading.Event()
    checkout = Caller(base + "/checkout", args.checkout_rps, stop, "checkout")
    neighbours = [Caller(base + "/" + n, args.neighbour_rps, stop, n)
                  for n in ("reports", "exports")]

    out = ROOT / "results"
    out.mkdir(exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    path = out / ("%s-%s.csv" % (args.label, stamp))
    fh = open(path, "w", newline="", encoding="utf-8")
    w = csv.writer(fh)
    w.writerow(["elapsed_s", "phase", "checkout_200", "checkout_502",
                "checkout_other", "neighbour_200", "neighbour_502"])

    print("recording : %s" % path)
    print()
    print("%8s  %-9s  %-26s  %s" % ("ELAPSED", "PHASE", "CHECKOUT", "NEIGHBOURS"))

    checkout.start()
    started = time.time()
    ramped = False

    try:
        while True:
            time.sleep(5)
            elapsed = int(time.time() - started)
            if elapsed >= args.seconds:
                break
            if not ramped and elapsed >= args.ramp_at:
                for n in neighbours:
                    n.start()
                ramped = True
                print("  -- neighbours on --")

            c = checkout.snapshot_and_reset()
            nb = Counter()
            for n in neighbours:
                nb.update(n.snapshot_and_reset())

            c200, c502 = c.get(200, 0), c.get(502, 0)
            cother = sum(v for k, v in c.items() if k not in (200, 502))
            phase = "load" if ramped else "baseline"
            w.writerow([elapsed, phase, c200, c502, cother, nb.get(200, 0), nb.get(502, 0)])
            fh.flush()

            total = c200 + c502 + cother
            pct = (100.0 * c200 / total) if total else 0.0
            print("%8d  %-9s  %3d ok  %3d 502  %3d other (%5.1f%%)  %4d ok  %4d 502"
                  % (elapsed, phase, c200, c502, cother, pct,
                     nb.get(200, 0), nb.get(502, 0)))
    finally:
        stop.set()
        time.sleep(1)
        fh.close()

    print()
    print("recorded  : %s" % path)
    print("summarise : python scripts/summarise.py %s" % path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
