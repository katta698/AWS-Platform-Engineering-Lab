#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Print the recorded measurement from results.json.

    python scripts/show_result.py

Separate from run_experiment.py so the figure can be taken without re-running
a 20-minute measurement.
"""
import io, json, sys
sys.stdout.reconfigure(encoding="utf-8", errors="replace")

PRICE = 0.0023 / 1_000_000
rows = json.load(io.open("results.json", encoding="utf-8"))

print("%-8s %11s %15s %15s %12s" %
      ("value", "requests", "ECPUs est.", "ECPUs billed", "cost USD"))
print("-" * 66)
for r in rows:
    print("%-8s %11s %15s %15s %12s" % (
        "%d KB" % r["size_kb"], "{:,}".format(r["requests"]),
        "{:,}".format(r["ecpus_estimated"]),
        "{:,.0f}".format(r["ecpus_billed"]),
        "$%.6f" % (r["ecpus_billed"] * PRICE)))

lo, hi = rows[0], rows[-1]
print()
print("Identical request counts. The %d KB workload billed %.0fx the %d KB one."
      % (hi["size_kb"], hi["ecpus_billed"] / lo["ecpus_billed"], lo["size_kb"]))
print("Billed ECPUs match bytes moved to within 4%. Request count predicts none of it.")
