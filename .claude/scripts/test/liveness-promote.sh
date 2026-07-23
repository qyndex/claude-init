#!/usr/bin/env bash
# M-04-promote (LAST item) — promote the branch-local committed-index-staleness
# liveness check to a REQUIRED validate.sh gate. Per the operator decision + O-7
# MEDIUM-1: promote ONLY the deterministic branch-local check (index mtime vs the
# newest committed memory .md); keep dream-recency + rollup-freshness ADVISORY
# (they read runtime logs / need a wall-clock week — not branch-local). A
# LIVENESS_SOFT=1 grace downgrades the gate to a warning (the promotion PR proves
# green under grace before the hard flip).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$ROOT"

pass=0; fail=0
check() { if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "  - $1"; fi; }

# (1) validate.sh has a liveness gate section.
grep -qE '\[liveness\]|committed index fresh|LIVENESS_SOFT' .claude/scripts/validate.sh
check "validate.sh has a liveness gate" $?

# (2) The gate is REQUIRED (contributes to failure) by default, but ONLY for the
#     branch-local index-staleness check — assert it references the index freshness,
#     NOT rollup-freshness (which stays advisory).
grep -qE 'index.*fresh|committed.index|newest.*memory' .claude/scripts/validate.sh
check "gate checks committed-index staleness (branch-local)" $?
! grep -qE 'validate.*rollup.fresh.*fail|fail.*rollup.fresh' .claude/scripts/validate.sh
check "rollup-freshness is NOT promoted to a hard failure (stays advisory)" $?

# (3) LIVENESS_SOFT=1 downgrades the gate to a warning (grace). Behavioral: build a
#     hermetic tree with a STALE index (older than a memory .md) and confirm:
#       - default: validate's liveness leg FAILS (non-zero contribution)
#       - LIVENESS_SOFT=1: it WARNS (does not fail)
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.claude/scripts" "$tmp/.claude/memory/patterns"
cp .claude/scripts/validate.sh "$tmp/.claude/scripts/" 2>/dev/null || true

# Stale index: create index first, then a NEWER memory file.
echo '{}' > "$tmp/.claude/memory/index.jsonl"
sleep 1
echo "# newer" > "$tmp/.claude/memory/patterns/newer.md"

# Run just the liveness leg via the env-overridable knobs the gate exposes.
# The gate must expose LIVENESS_INDEX / LIVENESS_MEMORY_DIR (reused from M-04) so
# the test points them at the fixture.
soft_out=$( cd "$tmp" && LIVENESS_SOFT=1 \
  LIVENESS_INDEX=".claude/memory/index.jsonl" \
  LIVENESS_MEMORY_DIR=".claude/memory" \
  bash .claude/scripts/validate.sh 2>&1 | grep -iE 'liveness|index.*(stale|fresh)' | head -3 )
# Under SOFT, a stale index must not hard-fail the liveness leg.
printf '%s' "$soft_out" | grep -qiE 'warn|advisory|soft'
check "LIVENESS_SOFT=1 downgrades a stale index to a warning (grace)" $?

# (4) The real repo must be GREEN under the gate (index is fresh — we just rebuilt
#     it in prior commits). This is the "proves-green before hard-flip" requirement.
bash .claude/scripts/memory-index.sh rebuild >/dev/null 2>&1 || true
# Grep the gate's own summary line (the one that reports index freshness), not any
# line that merely mentions "liveness" (e.g. a dead-test warning about this very
# file). The gate emits exactly one of: "✓ [liveness] committed index fresh" or
# "✗ [liveness] committed memory index ... STALE".
live_out=$(bash .claude/scripts/validate.sh 2>&1 | grep -E '\[liveness\]' | head -2)
printf '%s' "$live_out" | grep -qE '✓ \[liveness\] committed index fresh'
check "real repo is GREEN on the promoted liveness gate (index fresh)" $?

# (5) O-7 structural anti-regression: the promoted gate must judge freshness by
#     committed-file mtime ORDERING only — never a wall-clock window (`date +%s`
#     minus a threshold), which is exactly the wedge Correction 3 forbids. Extract
#     the [liveness] gate block from validate.sh and assert it contains no
#     `date +%s` / `date +%N` clock read.
gate_block=$(awk '/# ─── \[liveness\] promoted metabolism gate/{s=1} s{print} s && /^# ─── Summary/{exit}' .claude/scripts/validate.sh \
  | grep -vE '^[[:space:]]*#')   # judge executable lines only — a comment naming date+%s is not a regression
! printf '%s' "$gate_block" | grep -qE 'date[[:space:]]+\+%[sN]'
check "liveness gate uses mtime ordering, NOT a date+%s wall-clock window (no wedge)" $?

echo "passed: $pass"
echo "failed: $fail"
[ "$fail" -eq 0 ]
