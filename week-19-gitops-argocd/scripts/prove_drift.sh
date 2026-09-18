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

# START FROM A SETTLED CLUSTER, OR DO NOT START.
#
# This exists because two runs of this script disagreed with each other. Run 1
# said an out-of-band annotation survived; run 2 said it was removed. A
# controlled experiment then showed it survives -- both when idle and across a
# sync -- so run 2 was wrong.
#
# What made it wrong: run 1 ended by deleting the deployment, and Argo CD
# recreated it while run 2 was already measuring. The annotation was not
# stripped by anything; it was written to an object that then got replaced.
#
# A test that starts while the previous test's repair is still in flight is
# measuring the previous test. Waiting for the object to stop changing costs a
# few seconds and removes an entire class of false finding -- and this one was
# convincing enough that I had a plausible mechanism ready to publish for it.
echo "  waiting for the cluster to settle before measuring anything..."
stable=0
last_gen=""
for _ in $(seq 1 60); do
  gen=$(kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.metadata.generation}' 2>/dev/null)
  rdy=$(kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  if [[ -n "$gen" && "$gen" == "$last_gen" && "$rdy" == "$want_replicas" ]]; then
    stable=$((stable+1))
  else
    stable=0
  fi
  last_gen="$gen"
  [[ $stable -ge 5 ]] && break
  sleep 1
done
if [[ $stable -lt 5 ]]; then
  broke "cluster never settled -- refusing to measure a moving target"
  echo; echo "passed $pass  failed $fail  BROKEN $broken"; exit 3
fi
ok "settled: generation $last_gen stable, $want_replicas/$want_replicas ready"

# ---------------------------------------------------------------------------
# 1. Drift a field that IS in Git. This is the case GitOps advertises.
# ---------------------------------------------------------------------------
echo
echo "1. Change a field Git specifies (replicas)"

drifted=$((want_replicas + 2))

# metadata.generation increments on every change to .spec and never decreases.
# So a higher generation is proof the spec was mutated, even if the value was
# put back before we could look.
#
# The first version read .spec.replicas three seconds after scaling and called
# it BROKEN when it saw the original value: "wanted 4, saw 2". That was the
# honest report -- but the cause was not a failed scale. Argo CD reverted it in
# under three seconds. The test was slower than the thing it was measuring.
#
# Worth keeping in mind generally: when a controller's whole job is to undo
# your change, observing the change is a race you lose. Measure the fact that
# it happened, not the state it briefly produced.
gen_before=$(kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.metadata.generation}' 2>/dev/null)

if ! kubectl -n "$NS" scale deploy "$DEPLOY" --replicas="$drifted" >/dev/null 2>&1; then
  broke "could not apply the drift -- kubectl scale failed, so nothing was tested"
else
  sleep 3
  gen_after=$(kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.metadata.generation}' 2>/dev/null)
  now=$(kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.spec.replicas}')

  if [[ -z "$gen_after" || "$gen_after" == "$gen_before" ]]; then
    broke "generation did not move ($gen_before -> ${gen_after:-?}) -- the scale never landed, nothing was tested"
  else
    if [[ "$now" == "$want_replicas" ]]; then
      ok "drift applied AND already reverted (generation $gen_before -> $gen_after, replicas back to $want_replicas)"
      echo "         self-heal beat a 3-second observation window."
      pass=$((pass))   # already counted
      reverted="yes"
    else
      ok "drift applied: replicas $want_replicas -> $drifted (generation $gen_before -> $gen_after)"
      reverted=""
    fi

    if [[ "$reverted" != "yes" ]]; then
      echo "     waiting ${SETTLE}s for self-heal..."
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

# Identity, not absence.
#
# The first version of this check slept 3 seconds after the delete and looked
# for the object to be missing. Argo CD healed it faster than that, so the
# check reported BROKEN: "never observed the deployment absent". That was the
# honest answer -- it genuinely could not tell an instant heal from a rejected
# delete -- but it is a limitation of the observation, not a finding.
#
# A Kubernetes object's UID is assigned at creation and never changes. So a
# NEW uid is proof the old object was destroyed and a new one created, however
# briefly the gap lasted. That turns an unobservable window into a fact.
before_uid=$(kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.metadata.uid}' 2>/dev/null)
if [[ -z "$before_uid" ]]; then
  broke "could not read the deployment uid -- nothing was tested"
elif ! kubectl -n "$NS" delete deploy "$DEPLOY" --wait=false >/dev/null 2>&1; then
  broke "delete was rejected -- nothing was tested"
else
  ok "delete accepted (uid before: ${before_uid:0:8})"
  echo "     waiting ${SETTLE}s for Git to put it back..."
  new_uid=""
  for _ in $(seq 1 "$SETTLE"); do
    cur=$(kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.metadata.uid}' 2>/dev/null)
    if [[ -n "$cur" && "$cur" != "$before_uid" ]]; then new_uid="$cur"; break; fi
    sleep 1
  done
  if [[ -n "$new_uid" ]]; then
    ok "recreated from Git (uid after: ${new_uid:0:8}) -- different object, so it really was deleted"
  else
    still=$(kubectl -n "$NS" get deploy "$DEPLOY" -o jsonpath='{.metadata.uid}' 2>/dev/null)
    if [[ "$still" == "$before_uid" ]]; then
      broke "same uid after ${SETTLE}s -- the delete never took effect, nothing was tested"
    else
      bad "still missing after ${SETTLE}s -- self-heal did not restore a resource Git declares"
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
