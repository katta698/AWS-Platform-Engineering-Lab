#!/usr/bin/env bash
# Prove the tenancy boundary, rather than assert it.
#
# Four checks against the live cluster. The two that matter are the ones
# expected to FAIL:
#
#   1. tenant-a reaches its own bucket          -> must succeed  (Pod Identity)
#   2. tenant-a reaches tenant-b's bucket       -> must be DENIED
#   3. tenant-b reaches its own bucket          -> must succeed  (IRSA, Fargate)
#   4. tenant-b reaches tenant-a's bucket       -> must be DENIED
#
# Run 1 and 3 alone and you have shown that permissions work. Only 2 and 4 show
# that they stop anything.
#
# THE FIRST VERSION OF THIS SCRIPT REPORTED TWO PASSES AGAINST PODS THAT NEVER
# RAN. The tenant ResourceQuota requires every pod to declare cpu and memory
# requests AND limits; the probes declared none, so the admission controller
# rejected them before a container started. The checks looked only for denial
# strings, and a pod that never starts produces none -- which scored as success.
#
# Hence pod_never_ran() below. A test that cannot tell "denied" from "never ran"
# is not a test.
set -uo pipefail

CLUSTER="${CLUSTER:-week18-platform}"
A="${A_NS:-tenant-a}"
B="${B_NS:-tenant-b}"
IMAGE="${IMAGE:-public.ecr.aws/aws-cli/aws-cli:latest}"

pass=0
fail=0

# Build the pod spec as JSON, with resources, so the quota admits it.
overrides() {
  local sa="$1"; shift
  local cmd_json
  cmd_json=$(printf '"%s",' "$@" | sed 's/,$//')
  cat <<JSON
{"spec":{"serviceAccountName":"$sa","containers":[{"name":"probe","image":"$IMAGE","command":[$cmd_json],"resources":{"requests":{"cpu":"100m","memory":"128Mi"},"limits":{"cpu":"250m","memory":"256Mi"}}}]}}
JSON
}

# Fargate cold starts take about a minute before the container begins, so the
# timeout here is generous on purpose.
run_as_tenant() {
  local ns="$1" sa="$2"; shift 2
  kubectl run "probe-$RANDOM" \
    --namespace "$ns" \
    --image "$IMAGE" \
    --restart=Never --rm --attach --quiet \
    --pod-running-timeout=4m \
    --overrides="$(overrides "$sa" "$@")" \
    --command -- "$@" 2>&1
}

pod_never_ran() {
  grep -qiE "forbidden|failed quota|error from server|imagepullbackoff|createcontainererror|timed out waiting" <<<"$1"
}

expect() {
  local want="$1" desc="$2" output="$3"

  if pod_never_ran "$output"; then
    printf '  [FAIL] %s -- the pod never started, so this proves nothing\n' "$desc"
    printf '         %s\n' "$(head -c 150 <<<"$output" | tr '\n' ' ')"
    fail=$((fail + 1))
    return
  fi

  if [[ "$want" == "allow" ]]; then
    if grep -qiE "AccessDenied|not authorized|Unable to locate credentials" <<<"$output"; then
      printf '  [FAIL] %s -- expected success, was denied\n' "$desc"
      fail=$((fail + 1))
    else
      printf '  [ok]   %s\n' "$desc"
      pass=$((pass + 1))
    fi
  else
    if grep -qiE "AccessDenied|not authorized" <<<"$output"; then
      printf '  [ok]   %s -- denied, as it should be\n' "$desc"
      pass=$((pass + 1))
    else
      printf '  [FAIL] %s -- NOT denied. The boundary is not real.\n' "$desc"
      fail=$((fail + 1))
    fi
  fi
}

: "${BUCKET_A:?set BUCKET_A (terraform output tenant_a)}"
: "${BUCKET_B:?set BUCKET_B (terraform output tenant_b)}"

echo "Tenancy isolation test against cluster '$CLUSTER'"
echo

echo "1. $A -> its own bucket (Pod Identity, on EC2)"
expect allow "$A reads $BUCKET_A" "$(run_as_tenant "$A" app aws s3 ls "s3://$BUCKET_A")"

echo "2. $A -> $B's bucket"
expect deny "$A reads $BUCKET_B" "$(run_as_tenant "$A" app aws s3 ls "s3://$BUCKET_B")"

echo "3. $B -> its own bucket (IRSA, on Fargate)"
expect allow "$B reads $BUCKET_B" "$(run_as_tenant "$B" app aws s3 ls "s3://$BUCKET_B")"

echo "4. $B -> $A's bucket"
expect deny "$B reads $BUCKET_A" "$(run_as_tenant "$B" app aws s3 ls "s3://$BUCKET_A")"

echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
[[ $fail -eq 0 ]] || exit 1
