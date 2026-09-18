#!/usr/bin/env bash
# What does Argo CD's self-heal actually heal?
#
# GitOps' headline claim is that Git is the source of truth and the cluster
# converges back to it. That claim is true and narrower than it sounds, and
# this script is an attempt to find its edge rather than to demonstrate it.
#
# THE RULE THIS SCRIPT IS BUILT AROUND
# Week 18's isolation test reported two passes out of four against pods that
# never started. The ResourceQuota rejected them before any container ran, the
# checks only grepped the output for "denied", and work that never happens says
# nothing -- so "no denial found" scored as success. Two green ticks on two
# meaningless results.
#
# So every check here proves its own precondition before it reports anything.
# If the drift was never applied, that is a HARD FAILURE, never a pass. A test
# that cannot tell "reverted" from "never happened" is not a test, and green is
# what nobody investigates.
set -uo pipefail

NS="${DRIFT_NS:-gitops-demo}"
APP_NS="${APP_NS:-argocd}"
DEPLOY="${DEPLOY:-podinfo}"
SETTLE="${SETTLE:-90}"   # seconds to let Argo CD notice and act

pass=0; fail=0; broken=0

ok()     { printf '  [ok]     %s\n' "$1"; pass=$((pass+1)); }
bad()    { printf '  [FAIL]   %s\n' "$1"; fail=$((fail+1)); }
# A check that could not run is its own category. Folding it into "fail" is
# survivable; folding it into "pass" is how Week 18 shipped a green test that
# proved nothing.
broke()  { printf '  [BROKEN] %s\n' "$1"; broken=$((broken+1)); }

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1"; exit 2; }
}
need kubectl

# ---------------------------------------------------------------------------
# preconditions -- if these are not true, nothing below means anything
# ---------------------------------------------------------------------------
echo "Preconditions"

if ! kubectl get ns "$NS" >/dev/null 2>&1; then
  echo "  namespace $NS does not exist -- has the app synced yet?"; exit 2
fi
ok "namespace $NS exists"

if ! kubectl -n "$NS" get deploy "$DEPLOY" >/dev/null 2>&1; then
  echo "  deployment $DEPLOY not found in $NS -- nothing to drift"; exit 2
fi
ok "deployment $DEPLOY is deployed"

want_replicas=$(kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.spec.replicas}' 2>/dev/null)
if [[ -z "$want_replicas" ]]; then
  echo "  could not read current replica count"; exit 2
fi
ok "current desired replicas: $want_replicas"

# ---------------------------------------------------------------------------
# 1. Drift a field that IS in Git. This is the case GitOps advertises.
# ---------------------------------------------------------------------------
echo
echo "1. Change a field Git specifies (replicas)"

drifted=$((want_replicas + 2))
if ! kubectl -n "$NS" scale deploy "$DEPLOY" --replicas="$drifted" >/dev/null 2>&1; then
  broke "could not apply the drift -- kubectl scale failed, so nothing was tested"
else
  # PROVE the drift landed before waiting to see it reverted. Without this,
  # a scale that silently no-ops looks identical to a perfect self-heal.
  sleep 3
  now=$(kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.spec.replicas}')
  if [[ "$now" != "$drifted" ]]; then
    broke "drift did not take effect (wanted $drifted, saw $now) -- nothing was tested"
  else
    ok "drift applied: replicas $want_replicas -> $drifted"
    echo "     waiting ${SETTLE}s for self-heal..."
    reverted=""
    for _ in $(seq 1 "$SETTLE"); do
      cur=$(kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.spec.replicas}' 2>/dev/null)
      if [[ "$cur" == "$want_replicas" ]]; then reverted="yes"; break; fi
      sleep 1
    done
    if [[ "$reverted" == "yes" ]]; then
      ok "self-heal reverted it to $want_replicas"
    else
      bad "still $cur after ${SETTLE}s -- self-heal did not revert a tracked field"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 2. Drift a field Git does NOT specify.
#
# Argo CD compares against the desired state it was given. A field absent from
# that desired state has no target to converge to, so a three-way merge leaves
# it alone. This is correct behaviour and it is not what "the cluster matches
# Git" sounds like it means.
# ---------------------------------------------------------------------------
echo
echo "2. Add a field Git says nothing about (an annotation)"

stamp="drift-probe-$(date +%s)"
if ! kubectl -n "$NS" annotate deploy "$DEPLOY" "lab.week19/probe=$stamp" --overwrite >/dev/null 2>&1; then
  broke "could not annotate -- nothing was tested"
else
  got=$(kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath="{.metadata.annotations.lab\.week19/probe}" 2>/dev/null)
  if [[ "$got" != "$stamp" ]]; then
    broke "annotation did not land -- nothing was tested"
  else
    ok "annotation applied: $stamp"
    echo "     waiting ${SETTLE}s to see whether it is removed..."
    sleep "$SETTLE"
    still=$(kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath="{.metadata.annotations.lab\.week19/probe}" 2>/dev/null)
    if [[ "$still" == "$stamp" ]]; then
      ok "still present -- self-heal left it alone, as designed"
      echo "         Git is the source of truth for what Git MENTIONS."
    else
      bad "unexpectedly removed -- revisit the claim in the post before publishing"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# 3. Create a resource Git has never heard of, in the app's own namespace.
#
# The one that matters. Pruning removes resources the Application tracks and
# Git no longer declares. A resource created by hand carries no tracking
# annotation, so the Application does not consider it its own -- and an
# untracked resource is not drift, it is just furniture.
# ---------------------------------------------------------------------------
echo
echo "3. Create something Git never declared"

extra="rogue-$(date +%s)"
if ! kubectl -n "$NS" create configmap "$extra" --from-literal=note=not-in-git >/dev/null 2>&1; then
  broke "could not create the resource -- nothing was tested"
else
  ok "created configmap/$extra by hand"
  echo "     waiting ${SETTLE}s to see whether GitOps removes it..."
  sleep "$SETTLE"
  if kubectl -n "$NS" get configmap "$extra" >/dev/null 2>&1; then
    ok "still there -- not pruned, because it was never tracked"
    echo "         'the cluster matches Git' does not mean 'the cluster contains"
    echo "         only what Git declares'. Nothing here is misbehaving."
    kubectl -n "$NS" delete configmap "$extra" >/dev/null 2>&1 && \
      echo "         (cleaned up)"
  else
    bad "it was removed -- that contradicts the post's claim, check before publishing"
  fi
fi

# ---------------------------------------------------------------------------
# 4. Delete a resource Git DOES declare.
# ---------------------------------------------------------------------------
echo
echo "4. Delete a resource Git declares"

if ! kubectl -n "$NS" delete deploy "$DEPLOY" --wait=false >/dev/null 2>&1; then
  broke "could not delete -- nothing was tested"
else
  sleep 3
  gone_at_least_once="no"
  if ! kubectl -n "$NS" get deploy "$DEPLOY" >/dev/null 2>&1; then
    gone_at_least_once="yes"
  fi
  if [[ "$gone_at_least_once" == "no" ]]; then
    # It may have been recreated within our 3s window, which is a pass for
    # self-heal but means we never observed the precondition. Say so rather
    # than guess.
    broke "never observed the deployment absent -- cannot distinguish 'instantly healed' from 'delete rejected'"
  else
    ok "deployment deleted"
    echo "     waiting ${SETTLE}s for it to come back..."
    back=""
    for _ in $(seq 1 "$SETTLE"); do
      if kubectl -n "$NS" get deploy "$DEPLOY" >/dev/null 2>&1; then back="yes"; break; fi
      sleep 1
    done
    if [[ "$back" == "yes" ]]; then
      ok "recreated from Git"
    else
      bad "still missing after ${SETTLE}s"
    fi
  fi
fi

# ---------------------------------------------------------------------------
echo
echo "----------------------------------------------------------------"
printf 'passed %d   failed %d   BROKEN %d\n' "$pass" "$fail" "$broken"

if (( broken > 0 )); then
  echo
  echo "BROKEN checks did not run. They are not passes and they are not"
  echo "failures -- they are silence, and silence is what Week 18 published as"
  echo "success. Fix the precondition and run again before reporting anything."
  exit 3
fi

if (( fail > 0 )); then
  echo "Some behaviour did not match what the post intends to claim."
  exit 1
fi

echo "All checks ran and behaved as described."
