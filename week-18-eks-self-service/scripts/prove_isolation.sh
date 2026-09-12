#!/usr/bin/env bash
# Prove the tenancy boundary, rather than assert it.
#
# A namespace isolates nothing on its own. This runs four checks against the
# live cluster, and the two that matter are the ones expected to FAIL:
#
#   1. tenant-a reaches its own bucket          -> must succeed  (Pod Identity)
#   2. tenant-a reaches tenant-b's bucket       -> must be DENIED
#   3. tenant-b reaches its own bucket          -> must succeed  (IRSA, Fargate)
#   4. tenant-b reaches tenant-a's bucket       -> must be DENIED
#
# Run 1 and 3 alone and you have shown that permissions work. Only 2 and 4 show
# that they stop anything.
set -uo pipefail

CLUSTER="${CLUSTER:-week18-platform}"
REGION="${AWS_REGION:-us-east-1}"
A="${A_NS:-tenant-a}"
B="${B_NS:-tenant-b}"
IMAGE="${IMAGE:-public.ecr.aws/aws-cli/aws-cli:latest}"

pass=0
fail=0

# Run one AWS CLI command inside a tenant's namespace, as that tenant's service
# account, and report whether it succeeded.
#
# --restart=Never plus --rm gives a one-shot pod. The timeout matters on Fargate,
# where a cold start is roughly a minute before the container even begins.
run_as_tenant() {
  local ns="$1" sa="$2" desc="$3"; shift 3
  kubectl run "probe-$RANDOM" \
    --namespace "$ns" \
    --image "$IMAGE" \
    --restart=Never --rm --attach --quiet \
    --overrides="{\"spec\":{\"serviceAccountName\":\"$sa\"}}" \
    --command -- "$@" 2>&1
}

expect() {
  local want="$1" desc="$2" output="$3"
  if [[ "$want" == "allow" ]]; then
    if grep -qiE "AccessDenied|not authorized|Unable to locate credentials" <<<"$output"; then
      printf '  [FAIL] %s -- expected success, was denied\n' "$desc"; fail=$((fail+1))
    else
      printf '  [ok]   %s\n' "$desc"; pass=$((pass+1))
    fi
  else
    if grep -qiE "AccessDenied|not authorized" <<<"$output"; then
      printf '  [ok]   %s -- denied, as it should be\n' "$desc"; pass=$((pass+1))
    else
      printf '  [FAIL] %s -- NOT denied. The boundary is not real.\n' "$desc"; fail=$((fail+1))
    fi
  fi
}

echo "Tenancy isolation test against cluster '$CLUSTER'"
echo

BUCKET_A="${BUCKET_A:-}"
BUCKET_B="${BUCKET_B:-}"
if [[ -z "$BUCKET_A" || -z "$BUCKET_B" ]]; then
  echo "Set BUCKET_A and BUCKET_B (terraform output tenant_a / tenant_b)." >&2
  exit 2
fi

echo "1. $A -> its own bucket (Pod Identity, on EC2)"
out=$(run_as_tenant "$A" app "own" aws s3 ls "s3://$BUCKET_A")
expect allow "$A reads $BUCKET_A" "$out"

echo "2. $A -> $B's bucket"
out=$(run_as_tenant "$A" app "cross" aws s3 ls "s3://$BUCKET_B")
expect deny "$A reads $BUCKET_B" "$out"

echo "3. $B -> its own bucket (IRSA, on Fargate)"
out=$(run_as_tenant "$B" app "own" aws s3 ls "s3://$BUCKET_B")
expect allow "$B reads $BUCKET_B" "$out"

echo "4. $B -> $A's bucket"
out=$(run_as_tenant "$B" app "cross" aws s3 ls "s3://$BUCKET_A")
expect deny "$B reads $BUCKET_A" "$out"

echo
printf 'passed %d, failed %d\n' "$pass" "$fail"
[[ $fail -eq 0 ]] || exit 1
