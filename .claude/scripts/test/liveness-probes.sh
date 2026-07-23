#!/usr/bin/env bash
# Test for the M-04 liveness probes in harness-doctor.sh (advisory, env-parameterized).
#
# Tagged: AC-M04
#
# The three probes (stale committed index / dead dream / rollup gap) are exercised
# against hermetic fixtures injected through the env-override variables that mirror
# gc-suite.sh's GC_VERIFY_AGE_DAYS pattern. No real dream, no real auth, no wall
# clock: the "current week" is pinned via LIVENESS_NOW_WEEK. Each probe is asserted
# to emit `warn` on the dead/stale fixture and `pass` on the fresh fixture.
#
# CRITICAL (Correction 3): these probes are ADVISORY. This test also asserts that
# the liveness probes NEVER emit `fail` — hard-fail is deferred to M-04-promote.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
DOCTOR="$ROOT/.claude/scripts/harness-doctor.sh"

pass=0
fail=0
fails=()
expect() { local label="$1" rc="$2"; if [ "$rc" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); fails+=("$label"); fi; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Run harness-doctor with the spawn probe skipped (no OAuth in test) and capture
# the JSON status for a single check by label substring. Prints the status word.
status_of() {  # <check-substring>  (reads $DOCTOR_JSON)
  printf '%s' "$DOCTOR_JSON" | jq -r --arg c "$1" '.[] | select(.check | contains($c)) | .status' | head -1
}

# ─── Fixture: a committed memory tree where a memory .md is NEWER than the index ──
STALE_TREE="$TMP/stale-mem"
mkdir -p "$STALE_TREE"
: > "$STALE_TREE/index.jsonl"
# JUSTIFIED: BSD/GNU touch portability — set an OLD mtime on the index, a NEW one on the md
touch -t 202601010000 "$STALE_TREE/index.jsonl" 2>/dev/null || touch -d '2026-01-01' "$STALE_TREE/index.jsonl"
echo "# note" > "$STALE_TREE/note.md"
touch -t 202606010000 "$STALE_TREE/note.md" 2>/dev/null || touch -d '2026-06-01' "$STALE_TREE/note.md"

FRESH_TREE="$TMP/fresh-mem"
mkdir -p "$FRESH_TREE"
echo "# note" > "$FRESH_TREE/note.md"
touch -t 202601010000 "$FRESH_TREE/note.md" 2>/dev/null || touch -d '2026-01-01' "$FRESH_TREE/note.md"
: > "$FRESH_TREE/index.jsonl"
touch -t 202606010000 "$FRESH_TREE/index.jsonl" 2>/dev/null || touch -d '2026-06-01' "$FRESH_TREE/index.jsonl"

# ─── Fixture: dream logs (all failed, vs one recent success) ─────────────────────
DEAD_DREAM="$TMP/dead-dream"; mkdir -p "$DEAD_DREAM"
for d in 20260101 20260102 20260103; do
  echo "Not logged in · Please run /login" > "$DEAD_DREAM/dream-$d-000000.log"
done
LIVE_DREAM="$TMP/live-dream"; mkdir -p "$LIVE_DREAM"
echo "Not logged in · Please run /login" > "$LIVE_DREAM/dream-20260101-000000.log"
echo "dream complete: 3 patterns promoted" > "$LIVE_DREAM/dream-20260601-000000.log"
NO_DREAM="$TMP/no-dream"; mkdir -p "$NO_DREAM"

# ─── Fixture: rollup dirs (behind vs current week) ───────────────────────────────
STALE_ROLL="$TMP/stale-roll"; mkdir -p "$STALE_ROLL"
echo "# W24" > "$STALE_ROLL/2026-W24.md"
FRESH_ROLL="$TMP/fresh-roll"; mkdir -p "$FRESH_ROLL"
echo "# W30" > "$FRESH_ROLL/2026-W30.md"

# ═══════════════════════ Probe 1 — stale committed index ═════════════════════════
DOCTOR_JSON=$(HARNESS_DOCTOR_SKIP_SPAWN=1 \
  LIVENESS_INDEX="$STALE_TREE/index.jsonl" \
  LIVENESS_MEMORY_DIR="$STALE_TREE" \
  bash "$DOCTOR" --json 2>/dev/null)
[ "$(status_of 'committed index fresh')" = "warn" ]
expect "stale index → warn" $?

DOCTOR_JSON=$(HARNESS_DOCTOR_SKIP_SPAWN=1 \
  LIVENESS_INDEX="$FRESH_TREE/index.jsonl" \
  LIVENESS_MEMORY_DIR="$FRESH_TREE" \
  bash "$DOCTOR" --json 2>/dev/null)
[ "$(status_of 'committed index fresh')" = "pass" ]
expect "fresh index → pass" $?

# ═══════════════════════ Probe 2 — dead dream ════════════════════════════════════
DOCTOR_JSON=$(HARNESS_DOCTOR_SKIP_SPAWN=1 \
  LIVENESS_DREAM_DIR="$DEAD_DREAM" LIVENESS_DREAM_FAILS=3 \
  bash "$DOCTOR" --json 2>/dev/null)
[ "$(status_of 'dream has run recently')" = "warn" ]
expect "dead dream (3 failed) → warn" $?

DOCTOR_JSON=$(HARNESS_DOCTOR_SKIP_SPAWN=1 \
  LIVENESS_DREAM_DIR="$LIVE_DREAM" LIVENESS_DREAM_FAILS=3 \
  bash "$DOCTOR" --json 2>/dev/null)
[ "$(status_of 'dream has run recently')" = "pass" ]
expect "recent dream success → pass" $?

DOCTOR_JSON=$(HARNESS_DOCTOR_SKIP_SPAWN=1 \
  LIVENESS_DREAM_DIR="$NO_DREAM" LIVENESS_DREAM_FAILS=3 \
  bash "$DOCTOR" --json 2>/dev/null)
[ "$(status_of 'dream has run recently')" = "warn" ]
expect "no dream ever → warn" $?

# ═══════════════════════ Probe 3 — rollup gap ════════════════════════════════════
DOCTOR_JSON=$(HARNESS_DOCTOR_SKIP_SPAWN=1 \
  LIVENESS_ROLLUP_DIR="$STALE_ROLL" LIVENESS_ROLLUP_WEEKS=2 LIVENESS_NOW_WEEK=2026-W30 \
  bash "$DOCTOR" --json 2>/dev/null)
[ "$(status_of 'rollup freshness')" = "warn" ]
expect "rollup 6 weeks behind → warn" $?

DOCTOR_JSON=$(HARNESS_DOCTOR_SKIP_SPAWN=1 \
  LIVENESS_ROLLUP_DIR="$FRESH_ROLL" LIVENESS_ROLLUP_WEEKS=2 LIVENESS_NOW_WEEK=2026-W30 \
  bash "$DOCTOR" --json 2>/dev/null)
[ "$(status_of 'rollup freshness')" = "pass" ]
expect "rollup current week → pass" $?

# Deterministic-clock guard: no LIVENESS_NOW_WEEK → unknown warn, never invented wall-clock
DOCTOR_JSON=$(HARNESS_DOCTOR_SKIP_SPAWN=1 \
  LIVENESS_ROLLUP_DIR="$FRESH_ROLL" LIVENESS_ROLLUP_WEEKS=2 \
  bash "$DOCTOR" --json 2>/dev/null)
[ "$(status_of 'rollup freshness')" = "warn" ]
expect "rollup week unknown (no clock) → warn" $?

# ═══════════════════════ Correction-3 invariant — zero fail ══════════════════════
# The liveness probes must NEVER contribute a `fail` (advisory only). Point every
# probe at its dead/stale fixture at once and assert none of the three is `fail`.
DOCTOR_JSON=$(HARNESS_DOCTOR_SKIP_SPAWN=1 \
  LIVENESS_INDEX="$STALE_TREE/index.jsonl" LIVENESS_MEMORY_DIR="$STALE_TREE" \
  LIVENESS_DREAM_DIR="$DEAD_DREAM" LIVENESS_DREAM_FAILS=3 \
  LIVENESS_ROLLUP_DIR="$STALE_ROLL" LIVENESS_ROLLUP_WEEKS=2 LIVENESS_NOW_WEEK=2026-W30 \
  bash "$DOCTOR" --json 2>/dev/null)
liveness_fails=$(printf '%s' "$DOCTOR_JSON" | jq -r '[.[] | select((.check | test("committed index fresh|dream has run recently|rollup freshness")) and .status=="fail")] | length')
[ "$liveness_fails" = "0" ]
expect "liveness probes emit ZERO fail (Correction 3)" $?

echo "---"
echo "passed: $pass"
echo "failed: $fail"
if [ "$fail" -gt 0 ]; then
  printf '  - %s\n' "${fails[@]}"
  exit 1
fi
