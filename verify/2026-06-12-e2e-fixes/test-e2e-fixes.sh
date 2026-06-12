#!/usr/bin/env bash
# Campaign rig for the 2026-06-12 e2e-audit fixes — runs every per-item test
# matrix and summarizes. Two modes:
#
#   bash test-e2e-fixes.sh              # staged mode (pre-install): expects the
#                                       # 12 by-design validate.sh REDs that flip
#                                       # green only after staged/install.sh
#   INSTALLED=1 bash test-e2e-fixes.sh  # installed mode (post-install): expects
#                                       # validate.sh fully green (0 failures)
#
# Every matrix is self-contained; a matrix exiting non-zero fails the rig.

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
cd "$ROOT"

INSTALLED="${INSTALLED:-0}"
total_pass=0; total_fail=0; suites_fail=0

run_suite() {
  local name="$1"
  echo
  echo "════ $name ════"
  if out=$(bash "$HERE/$name" 2>&1); then
    line=$(echo "$out" | tail -1)
    echo "  ✓ $line"
  else
    suites_fail=$((suites_fail+1))
    echo "$out" | grep -E '^FAIL|fail$' | head -10
    echo "  ✗ SUITE FAILED: $name"
  fi
  p=$(echo "$out" | tail -1 | grep -oE '[0-9]+ pass' | grep -oE '[0-9]+' || echo 0)
  f=$(echo "$out" | tail -1 | grep -oE '[0-9]+ fail' | grep -oE '[0-9]+' || echo 0)
  total_pass=$((total_pass + p)); total_fail=$((total_fail + f))
}

# Per-item matrices (campaign order)
for suite in \
  test-workflow-state.sh \
  test-next-task.sh \
  test-accept-rerun.sh \
  test-loop-meta.sh \
  test-morning-banners.sh \
  test-orphan-reconcile.sh \
  test-bash-guard-cases.sh \
  test-lane-guard.sh \
  test-swarm-root.sh \
  test-fleet-reconcile.sh \
  test-verified-merge.sh \
  test-adopt-gate.sh \
  test-adopt-completeness.sh \
  test-deploy-gate.sh \
  test-flag-ramp.sh \
  test-ci-plumbing.sh \
  test-dep-cache.sh \
  test-hygiene.sh \
  test-actor-artifact.sh \
  test-doc-truth.sh \
  test-doc-claims.sh \
  test-stack-portability.sh \
; do
  [ -f "$HERE/$suite" ] || { echo "MISSING SUITE: $suite"; suites_fail=$((suites_fail+1)); continue; }
  run_suite "$suite"
done

# Mode-dependent validate.sh expectation
echo
echo "════ validate.sh (mode: $([ "$INSTALLED" = 1 ] && echo installed || echo staged)) ════"
vout=$(bash .claude/scripts/validate.sh 2>&1)
vfails=$(echo "$vout" | grep -oE '✗ [0-9]+ failures' | grep -oE '[0-9]+' || true)
vfails="${vfails:-0}"
if [ "$INSTALLED" = 1 ]; then
  if [ "$vfails" -eq 0 ]; then
    echo "  ✓ validate.sh fully green post-install (0 failures)"
  else
    echo "  ✗ validate.sh still has $vfails failures post-install:"
    echo "$vout" | grep '✗' | head -15
    suites_fail=$((suites_fail+1))
  fi
else
  # Staged mode: exactly the 12 by-design pre-install REDs, no more, no fewer.
  # 4 ephemeral-verb + 2 alwaysLoad-matcher + 1 claude.yml actor guard +
  # 4 handoff-dialect refs + 1 model-doc drift (§V anti-slop-reviewer).
  if [ "$vfails" -eq 12 ]; then
    echo "  ✓ validate.sh shows exactly the 12 by-design pre-install REDs"
  else
    echo "  ✗ expected 12 by-design pre-install REDs, got $vfails:"
    echo "$vout" | grep '✗' | head -16
    suites_fail=$((suites_fail+1))
  fi
fi

echo
echo "═════════════════════════════════════════"
echo "campaign rig: $total_pass pass / $total_fail fail across matrices; $suites_fail suite-level failure(s)"
[ "$total_fail" -eq 0 ] && [ "$suites_fail" -eq 0 ]
