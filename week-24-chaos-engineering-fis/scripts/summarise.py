#!/usr/bin/env python3
"""Turn a recorded experiment into the four numbers the week is about.

    python scripts/summarise.py results/typical-20261023T201500Z.csv
    python scripts/summarise.py results/*.csv        # compare runs

THE NUMBERS
-----------
  impact began     first second a target was not healthy
  alarm fired      first second the guarding alarm went to ALARM
  experiment ended first second FIS reported stopped/completed
  damage window    impact began -> experiment ended

The last one is the point. A stop condition is sold as a safety net, and the
net cannot close faster than its alarm evaluates. This measures the gap.

Deliberately reports "never" rather than a blank where an alarm did not fire.
A missing number and a number of zero are different claims, and the difference
is the whole finding in the case where the slow alarm never fires at all.
"""
import csv
import sys
from pathlib import Path


def load(path):
    with open(path, newline="", encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def first_where(rows, pred):
    for r in rows:
        if pred(r):
            return int(r["elapsed_s"])
    return None


def fmt(v):
    if v is None:
        return "never"
    if isinstance(v, str):
        return v
    return f"{v}s"


def summarise(path):
    rows = load(path)
    if not rows:
        return None

    label = Path(path).stem.split("-")[0]

    impact = first_where(rows, lambda r: int(r["unhealthy"] or 0) > 0
                                         or int(r["healthy"] or 0) < 4)
    fast = first_where(rows, lambda r: r["alarm_fast"] == "ALARM")
    typical = first_where(rows, lambda r: r["alarm_typical"] == "ALARM")
    ended = first_where(rows, lambda r: r["fis_state"] in ("stopped", "completed", "failed"))

    # Which alarm was actually guarding this run decides which gap matters.
    guard = {"fast": fast, "typical": typical}.get(label)

    damage = None
    if impact is not None and ended is not None:
        damage = ended - impact
        if damage < 0:
            # The fault landed after FIS reported terminal. That is not a
            # measurement, it is the recorder having stopped watching too
            # early -- report it as such rather than printing a negative
            # number that a reader would take for a real duration.
            damage = "LATE"


    recovered = first_where(
        [r for r in rows if int(r["elapsed_s"]) > (impact or 0)],
        lambda r: int(r["healthy"] or 0) >= 4 and int(r["unhealthy"] or 0) == 0)

    return {
        "run": Path(path).name,
        "guard": label,
        "impact": impact,
        "fast": fast,
        "typical": typical,
        "guard_fired": guard,
        "ended": ended,
        "damage": damage,
        "recovered": recovered,
    }


def main():
    paths = sys.argv[1:]
    if not paths:
        sys.exit(__doc__)

    results = [s for s in (summarise(p) for p in paths) if s]
    if not results:
        sys.exit("no rows in any of those files")

    w = "  {:<22} {:>8} {:>8} {:>9} {:>9} {:>9}"
    print()
    print(w.format("run", "impact", "guard", "ended", "DAMAGE", "recovered"))
    print("  " + "-" * 70)
    for r in results:
        print(w.format(
            r["guard"], fmt(r["impact"]), fmt(r["guard_fired"]),
            fmt(r["ended"]), fmt(r["damage"]), fmt(r["recovered"])))
    print()

    # The comparison only means anything if both guarded runs are present.
    by_guard = {r["guard"]: r for r in results}
    if "fast" in by_guard and "typical" in by_guard:
        f, t = by_guard["fast"], by_guard["typical"]
        numeric = all(isinstance(x["damage"], int) for x in (f, t))
        if numeric:
            delta = t["damage"] - f["damage"]
            print(f"  Same fault, same duration. The only difference is the alarm.")
            print(f"  fast alarm   : {f['damage']}s of damage")
            print(f"  typical alarm: {t['damage']}s of damage")
            print(f"  cost of the slower alarm: {delta}s "
                  f"({delta / 60:.1f} minutes) of additional impact")
            print()
        elif t["damage"] is None:
            print("  The typical alarm never stopped the experiment. It ran to its")
            print("  full duration -- the safety net was never going to close in time.")
            print()


if __name__ == "__main__":
    main()
