# Ten calls across three principals and two paths to the same table.
# Each case declares what it expects BEFORE it runs, and the script exits
# non-zero if any case disagrees -- three of them expect to be allowed
# something they should not be.

cd ../../..
python scripts/prove_isolation.py
