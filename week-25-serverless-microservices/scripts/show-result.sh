#!/usr/bin/env bash
# The comparison, read back from the recordings rather than retyped.
#
# Picks the newest run1 and run2 CSV in results/ so the figure cannot drift
# from the evidence: if a run is re-recorded, this shows the new one.
set -euo pipefail
cd "$(dirname "$0")/.."

RUN1=$(ls -t results/run1-unprotected-*.csv | head -1)
RUN2=$(ls -t results/run2-protected-*.csv | head -1)

python scripts/summarise.py "$RUN1" "$RUN2"
