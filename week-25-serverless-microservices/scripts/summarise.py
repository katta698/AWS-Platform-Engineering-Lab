#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Turn one or both recordings into the number the week is about.

    python scripts/summarise.py results/*.csv

THE NUMBER
----------
checkout's success rate during the load phase. Not the neighbours' -- they are
supposed to be busy. The claim is that a service nobody touched degrades
because of what its neighbours did, so the measurement is checkout's, and it is
taken from the client because a throttled invocation leaves no trace inside the
function that suffered it.

Reports "no load phase recorded" rather than 100% when a run never ramped. An
absent measurement and a perfect one are different claims, and at a glance they
print the same way.
"""
import csv
import sys
from pathlib import Path


def load(p):
    with open(p, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def summarise(path):
    rows = load(path)
    if not rows:
        return None
    base = [r for r in rows if r["phase"] == "baseline"]
    load_ = [r for r in rows if r["phase"] == "load"]

    def rate(rs):
        ok = sum(int(r["checkout_200"]) for r in rs)
        bad = sum(int(r["checkout_502"]) + int(r["checkout_other"]) for r in rs)
        return (ok, bad, (100.0 * ok / (ok + bad)) if (ok + bad) else None)

    b_ok, b_bad, b_pct = rate(base)
    l_ok, l_bad, l_pct = rate(load_)
    return {
        "run": Path(path).name,
        "baseline": b_pct, "baseline_n": b_ok + b_bad,
        "load": l_pct, "load_n": l_ok + l_bad, "load_failed": l_bad,
    }


def fmt(v):
    return "no data" if v is None else "%.1f%%" % v


def main():
    paths = sys.argv[1:]
    if not paths:
        sys.exit(__doc__)
    res = [s for s in (summarise(p) for p in paths) if s]
    if not res:
        sys.exit("no rows in any of those files")

    print()
    print("  %-34s %12s %12s %10s" % ("run", "baseline", "under load", "failed"))
    print("  " + "-" * 72)
    for r in res:
        print("  %-34s %12s %12s %10s"
              % (r["run"][:34], fmt(r["baseline"]), fmt(r["load"]),
                 r["load_failed"] if r["load"] is not None else "-"))
        if r["load"] is None:
            print("       no load phase recorded -- the neighbours never ramped")
    print()

    runs = {("protected" if "run2" in r["run"] else "unprotected"): r for r in res}
    if "unprotected" in runs and "protected" in runs:
        u, p = runs["unprotected"], runs["protected"]
        if u["load"] is not None and p["load"] is not None:
            print("  Same load, same code, same region. The only difference is whether")
            print("  checkout reserved concurrency.")
            print()
            print("    unprotected : %s of checkout requests succeeded under load" % fmt(u["load"]))
            print("    protected   : %s" % fmt(p["load"]))
            print()
            if u["load"] < p["load"]:
                print("  checkout was starved by services it does not call, does not")
                print("  depend on, and shares nothing with except an account.")
            print()


if __name__ == "__main__":
    main()
