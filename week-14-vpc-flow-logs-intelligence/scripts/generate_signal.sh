#!/usr/bin/env bash
#
# Produce a deliberate, recognisable signal in the flow logs.
#
# The exposed instance collects genuine internet background scanning on its own,
# but that traffic arrives on whatever schedule the internet feels like. This
# script generates a known pattern from a known source address so the detection
# queries can be demonstrated against something identifiable, at a chosen moment.
#
# It connects to ports on an instance in your own account, in a VPC you built,
# whose security group denies every one of those connections. Nothing is
# exploited and nothing gets through -- the point is to have the security group
# reject a fan-out pattern so the REJECT records exist to be queried.
#
# Usage:
#   ./generate_signal.sh <exposed-instance-public-ip> [port-count]
#
# Get the IP from the apply:
#   terraform output -raw exposed_instance_public_ip
#
# Then wait ~15 minutes for delivery before querying. Flow logs reach S3 in
# roughly 10 minutes and are written in 5-minute batches; querying sooner shows
# nothing and looks like a broken pipeline.

set -uo pipefail

TARGET="${1:-}"
PORT_COUNT="${2:-40}"

if [[ -z "$TARGET" ]]; then
  echo "usage: $0 <exposed-instance-public-ip> [port-count]" >&2
  echo >&2
  echo "  terraform output -raw exposed_instance_public_ip" >&2
  exit 1
fi

if ! [[ "$TARGET" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: '$TARGET' is not an IPv4 address" >&2
  exit 1
fi

echo "Target:      $TARGET"
echo "Ports:       $PORT_COUNT distinct"
echo "Source:      $(curl -s -m 5 https://checkip.amazonaws.com 2>/dev/null || echo 'unknown')"
echo
echo "Every connection below is expected to fail. The security group has no"
echo "ingress rules, so each attempt becomes a REJECT record in the flow logs."
echo

###############################################################################
# Fan-out across distinct ports.
#
# Fan-out is what distinguishes a scan from a broken client in the detection
# query -- a stuck client retries ONE port forever, a scan walks the range. The
# port-scan query threshold is 20 distinct ports, so the default of 40 clears it
# with margin.
###############################################################################

echo "--- Port fan-out ---"

# A spread of commonly-probed ports, then a contiguous block to reach the count.
PORTS=(21 22 23 25 53 80 110 135 139 143 443 445 993 995 1433 1521 3306 3389 5432 5900 6379 8080 8443 9200 11211 27017)

i=0
for p in "${PORTS[@]}"; do
  [[ $i -ge $PORT_COUNT ]] && break
  timeout 1 bash -c "echo > /dev/tcp/${TARGET}/${p}" 2>/dev/null
  printf '.'
  i=$((i + 1))
done

p=10000
while [[ $i -lt $PORT_COUNT ]]; do
  timeout 1 bash -c "echo > /dev/tcp/${TARGET}/${p}" 2>/dev/null
  printf '.'
  i=$((i + 1))
  p=$((p + 1))
done

echo
echo "  $i connection attempts made, all expected to have been rejected."

###############################################################################
# Repeat traffic to one port.
#
# The other shape the rejected-traffic query groups on: high count, low spread.
# Included so the two queries can be shown returning genuinely different things
# rather than the same rows twice.
###############################################################################

echo
echo "--- Repeat attempts against a single port ---"

for _ in $(seq 1 25); do
  timeout 1 bash -c "echo > /dev/tcp/${TARGET}/8080" 2>/dev/null
  printf '.'
done

echo
echo "  25 attempts against port 8080."

###############################################################################

cat <<'EOF'

Done.

Wait ~15 minutes for delivery, then run in the Athena console (workgroup
week14-flowlogs-wg):

  week14-flowlogs-partition-sanity-check    confirm data is readable at all
  week14-flowlogs-port-scan-candidates      should now show this source
  week14-flowlogs-rejected-traffic          should show both shapes above

Or force an analyzer run rather than waiting for the hourly schedule:

  aws lambda invoke --function-name week14-flowlogs-flow-analyzer out.json \
    && cat out.json && rm out.json

EOF
